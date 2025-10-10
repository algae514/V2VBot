const logEl = document.getElementById('log');
const statusEl = document.getElementById('status');
const transcriptEl = document.getElementById('transcript');
const startBtn = document.getElementById('start');

let pc;
let dc;
let micStream;
let statsTimer = null;

function log(...args) {
	const line = args.map(String).join(' ');
	console.log('[ui]', line);
	logEl.textContent += line + '\n';
}

function onUnhandledRejection(ev) {
	log('unhandledrejection', ev.reason || 'unknown');
}
window.addEventListener('unhandledrejection', onUnhandledRejection);

async function startSenderStats() {
	if (!pc) return;
	const sender = pc.getSenders().find(s => s.track && s.track.kind === 'audio');
	if (!sender) return;
	let lastBytes = 0;
	let lastTs = 0;
	if (statsTimer) clearInterval(statsTimer);
	statsTimer = setInterval(async () => {
		try {
			const report = await sender.getStats();
			report.forEach(stat => {
				if (stat.type === 'outbound-rtp' && !stat.isRemote) {
					const bytes = stat.bytesSent || 0;
					const ts = stat.timestamp || Date.now();
					if (lastTs) {
						const deltaB = bytes - lastBytes;
						const deltaT = (ts - lastTs) / 1000;
						if (deltaT > 0) {
							const kbps = ((deltaB * 8) / 1000) / deltaT;
							log('send kbps', kbps.toFixed(1));
						}
					}
					lastBytes = bytes;
					lastTs = ts;
				}
			});
		} catch (e) {
			// ignore
		}
	}, 1000);
}

async function createPeerAndConnect(stream) {
	pc = new RTCPeerConnection({
		iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
	});

	pc.onicecandidate = (e) => log('ice candidate', !!e.candidate);
	pc.onicegatheringstatechange = () => log('ice gathering', pc.iceGatheringState);
	pc.oniceconnectionstatechange = () => log('ice state', pc.iceConnectionState);
	pc.onconnectionstatechange = () => log('pc state', pc.connectionState);
	pc.onnegotiationneeded = () => log('negotiationneeded');
	pc.onsignalingstatechange = () => log('signaling', pc.signalingState);

	for (const track of stream.getAudioTracks()) {
		log('addTrack', track.kind);
		pc.addTrack(track, stream);
	}

	pc.ontrack = (e) => {
		log('ontrack', e.track.kind);
		const [down] = e.streams;
		const audioEl = new Audio();
		audioEl.autoplay = true;
		audioEl.srcObject = down;
		statusEl.textContent = 'Connected';
	};

	log('creating datachannel');
	dc = pc.createDataChannel('control');
	dc.onopen = () => log('dc open');
	dc.onclose = () => log('dc close');
	dc.onerror = (e) => log('dc error', e && e.message);
	dc.onmessage = (ev) => {
		log('dc message', ev.data);
		try {
			const msg = JSON.parse(ev.data);
			if (msg.partial) transcriptEl.textContent = msg.partial;
			if (msg.final) transcriptEl.textContent = msg.final;
			if (msg.ok) log('server ok');
			if (msg.audio) log('server audio', 'fps', msg.audio.fps, 'rms', msg.audio.rms);
		} catch (e) {
			// ignore parse errors
		}
	};

	log('creating offer');
	const offer = await pc.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: false });
	await pc.setLocalDescription(offer);
	log('localDescription set');

	log('posting offer to /api/offer');
	const resp = await fetch('/api/offer', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ sdp: offer.sdp, type: offer.type })
	});
	if (!resp.ok) {
		const text = await resp.text();
		throw new Error('offer failed ' + resp.status + ' ' + text);
	}
	const ans = await resp.json();
	log('answer received');
	await pc.setRemoteDescription(ans);
	log('remoteDescription set');
	startSenderStats();
}

async function startMic() {
	startBtn.disabled = true;
	try {
		log('requesting mic');
		
		// Absolute bare minimum - let browser use native format with NO processing
		micStream = await navigator.mediaDevices.getUserMedia({
			audio: {
				channelCount: 1
				// No constraints at all - browser uses native capture format
			},
			video: false
		});
		log('got mic');
		await createPeerAndConnect(micStream);
	} catch (err) {
		log('error', err && (err.stack || err.message || String(err)));
		startBtn.disabled = false;
	}
}

startBtn.addEventListener('click', () => startMic().catch((e) => log('fatal', e && e.message)));
