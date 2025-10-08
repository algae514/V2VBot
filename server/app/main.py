import asyncio
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from typing import Optional

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from aiortc import RTCPeerConnection, RTCSessionDescription
from aiortc.contrib.media import MediaBlackhole
from aiortc.mediastreams import MediaStreamTrack
import numpy as np
import time

from .audio.pipeline import AudioPipeline

# Configure logging: console + rotating file
os.makedirs("logs", exist_ok=True)
_formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
_file_handler = RotatingFileHandler("logs/server.log", maxBytes=5 * 1024 * 1024, backupCount=3)
_file_handler.setFormatter(_formatter)
logging.basicConfig(level=logging.INFO, handlers=[_file_handler, logging.StreamHandler()])
logger = logging.getLogger("uvicorn.error")

app = FastAPI()

# Serve JS assets and public static files
app.mount("/assets", StaticFiles(directory="web/src", html=False), name="assets")
app.mount("/static", StaticFiles(directory="web/public", html=False), name="static")

@app.get("/")
async def index() -> FileResponse:
	return FileResponse("web/public/index.html")

pcs: set[RTCPeerConnection] = set()


async def _log_inbound_stats(pc: RTCPeerConnection) -> None:
	last_bytes = 0
	last_ts = 0
	try:
		while pc.connectionState not in ("closed", "failed", "disconnected"):
			await asyncio.sleep(1)
			try:
				report = await pc.getStats()
				for stat in report.values():
					if stat.type == "inbound-rtp" and stat.kind == "audio" and not getattr(stat, "isRemote", False):
						bytes_now = getattr(stat, "bytesReceived", 0) or 0
						ts = getattr(stat, "timestamp", 0) or 0
						if last_ts and ts > last_ts:
							delta_b = bytes_now - last_bytes
							delta_t = (ts - last_ts) / 1000
							if delta_t > 0:
								kbps = ((delta_b * 8) / 1000) / delta_t
								logger.info("inbound kbps=%.1f", kbps)
						last_bytes = bytes_now
						last_ts = ts
			except Exception:
				pass
	except Exception:
		pass


@app.on_event("shutdown")
async def on_shutdown() -> None:
	coros = [pc.close() for pc in pcs]
	await asyncio.gather(*coros, return_exceptions=True)
	pcs.clear()


@app.post("/api/offer")
async def offer(request: Request) -> JSONResponse:
	try:
		payload = await request.json()
		sdp = payload.get("sdp")
		type_ = payload.get("type")
		logger.info("/api/offer received type=%s len(sdp)=%s", type_, len(sdp) if sdp else None)
		if not sdp or not type_:
			return JSONResponse({"error": "invalid offer"}, status_code=400)

		pc = RTCPeerConnection()
		pcs.add(pc)

		media_blackhole = MediaBlackhole()
		refs = {"ch": None}

		@pc.on("connectionstatechange")
		def on_pc_state():
			logger.info("pc state=%s", pc.connectionState)

		@pc.on("iceconnectionstatechange")
		def on_ice_state():
			logger.info("ice state=%s", pc.iceConnectionState)

		@pc.on("datachannel")
		def on_datachannel(channel):
			logger.info("DataChannel created: %s", channel.label)
			refs["ch"] = channel

			@channel.on("message")
			def on_message(message):
				if isinstance(message, str):
					logger.info("dc<= %s", message)

			async def _ping():
				while True:
					await asyncio.sleep(10)
					if refs["ch"] is None:
						break
					try:
						refs["ch"].send('{"ping":true}')
					except Exception:
						break
			asyncio.create_task(_ping())

		@pc.on("track")
		async def on_track(track: MediaStreamTrack):
			logger.info("Track received: kind=%s", track.kind)
			if track.kind == "audio":
				pipeline = AudioPipeline(lambda payload: refs["ch"] and refs["ch"].send(payload))
				await media_blackhole.start()
				frames = 0
				last_log = time.monotonic()
				last_rms = 0.0
				try:
					while True:
						frame = await track.recv()
						pcm = frame.to_ndarray(format="s16").astype(np.int16)
						pcm = pcm.reshape(-1)
						pcm_f32 = (pcm.astype(np.float32) / 32768.0)
						for i in range(0, len(pcm_f32), 960):
							chunk = pcm_f32[i:i+960]
							if len(chunk) < 960:
								break
							last_rms = float(np.sqrt(np.mean(chunk * chunk)))
							await pipeline.handle_audio_frame(chunk)
							frames += 1
							now = time.monotonic()
							if now - last_log >= 1.0:
								logger.info("audio frames/s=%d rms=%.3f", frames, last_rms)
								print(f"audio frames/s={frames} rms={last_rms:.3f}")
								try:
									if refs["ch"]:
										refs["ch"].send(json.dumps({"audio":{"fps": frames, "rms": round(last_rms, 3)}}))
								except Exception:
									pass
								frames = 0
								last_log = now
				except Exception as e:
					logger.exception("audio loop error")
					print("audio loop error", e)
				finally:
					await media_blackhole.stop()

		# Apply remote offer
		offer_desc = RTCSessionDescription(sdp=sdp, type=type_)
		await pc.setRemoteDescription(offer_desc)

		# Start inbound stats logger
		asyncio.create_task(_log_inbound_stats(pc))

		# Create and set local answer
		answer = await pc.createAnswer()
		await pc.setLocalDescription(answer)

		return JSONResponse({"sdp": pc.localDescription.sdp, "type": pc.localDescription.type})
	except Exception as e:
		logger.exception("/api/offer failed")
		return JSONResponse({"error": str(e)}, status_code=500)
