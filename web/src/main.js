const logEl = document.getElementById('log');
const statusEl = document.getElementById('status');
const transcriptEl = document.getElementById('transcript');
const llmResponseEl = document.getElementById('llm-response');
const startBtn = document.getElementById('start');

let pc;
let dc;
let micStream;
let micTrack = null; // Microphone track for muting
let statsTimer = null;
let audioContext = null;
let audioQueue = [];
let audioQueueMap = new Map(); // Map of sequence number -> audio chunk for ordered playback
let nextExpectedSequence = 0; // Next expected sequence number
let isPlayingAudio = false;
let currentAudioSource = null; // Track current playing audio for interruption
let audioCleanupTimer = null; // Timer for cleanup
let maxAudioQueueSize = 50; // Increased to handle longer responses (prevent memory buildup)
let audioGainNode = null; // Gain node for immediate volume control
let isInterrupted = false; // Flag to track interruption state

function log(...args) {
	const line = args.map(String).join(' ');
	// console.log('[ui]', line);
	// Only append to logEl if not a tts_chunk message
	if (!line.includes('tts_chunk')) {
		logEl.textContent += line + '\n';
	}
}

async function initAudioContext() {
	if (!audioContext) {
		try {
			audioContext = new (window.AudioContext || window.webkitAudioContext)();
			
			// Create gain node for immediate volume control
			audioGainNode = audioContext.createGain();
			audioGainNode.connect(audioContext.destination);
			
			log('🎵 Audio context initialized with gain control');
		} catch (error) {
			log('❌ Failed to initialize audio context:', error);
			throw error;
		}
	}
	
	// Resume context if suspended
	if (audioContext.state === 'suspended') {
		try {
			await audioContext.resume();
		} catch (error) {
			log('❌ Failed to resume audio context:', error);
		}
	}
	
	return audioContext;
}

async function playAudioChunk(audioData, sampleRate) {
	try {
		const ctx = await initAudioContext();
		
		// Check for interruption before starting
		if (isInterrupted) {
			log('🔇 Audio playback cancelled due to interruption');
			return;
		}
		
		// Convert base64 to ArrayBuffer
		const binaryString = atob(audioData);
		const bytes = new Uint8Array(binaryString.length);
		for (let i = 0; i < binaryString.length; i++) {
			bytes[i] = binaryString.charCodeAt(i);
		}
		
		// Convert to AudioBuffer
		const audioBuffer = ctx.createBuffer(1, bytes.length / 2, sampleRate);
		const channelData = audioBuffer.getChannelData(0);
		
		// Convert int16 to float32
		for (let i = 0; i < bytes.length / 2; i++) {
			const sample = (bytes[i * 2] | (bytes[i * 2 + 1] << 8));
			channelData[i] = sample < 32768 ? sample / 32768 : (sample - 65536) / 32768;
		}
		
		// Play audio and return promise that resolves when finished
		const source = ctx.createBufferSource();
		source.buffer = audioBuffer;
		
		// Connect through gain node for immediate volume control
		source.connect(audioGainNode);
		
		// Track current audio source for interruption
		currentAudioSource = source;
		
		return new Promise((resolve) => {
			// Set up interruption monitoring
			const checkInterruption = () => {
				if (isInterrupted) {
					log('🔇 Audio playback interrupted during playback');
					try {
						source.stop();
						source.disconnect();
					} catch (error) {
						// Ignore errors
					}
					currentAudioSource = null;
					resolve();
					return true;
				}
				return false;
			};
			
			source.onended = () => {
				log(`🔊 Finished playing audio chunk: ${audioBuffer.length} samples at ${sampleRate}Hz`);
				currentAudioSource = null;
				resolve();
			};
			
			// Check for interruption right before starting
			if (checkInterruption()) {
				return;
			}
			
			source.start();
			log(`🔊 Playing audio chunk: ${audioBuffer.length} samples at ${sampleRate}Hz`);
			
			// Monitor for interruption during playback (check every 50ms)
			const interruptionMonitor = setInterval(() => {
				if (checkInterruption()) {
					clearInterval(interruptionMonitor);
				}
			}, 50);
			
			// Clean up monitor when audio ends
			source.onended = () => {
				clearInterval(interruptionMonitor);
				log(`🔊 Finished playing audio chunk: ${audioBuffer.length} samples at ${sampleRate}Hz`);
				currentAudioSource = null;
				resolve();
			};
		});
		
	} catch (error) {
		log('❌ Audio playback error:', error);
		throw error;
	}
}

function interruptAudioPlayback() {
	// Set interruption flag immediately
	isInterrupted = true;
	
	// IMMEDIATE: Set volume to 0 using gain node (instant silence)
	if (audioGainNode) {
		audioGainNode.gain.setValueAtTime(0, audioContext.currentTime);
		log('🔇 Audio volume set to 0 (immediate silence)');
	}
	
	// Unmute microphone immediately for user input
	unmuteMicrophone();
	
	// Stop current audio source IMMEDIATELY
	if (currentAudioSource) {
		try {
			currentAudioSource.stop();
			currentAudioSource.disconnect(); // Properly disconnect
			log('🔇 Stopped and disconnected current audio source');
		} catch (error) {
			// Audio source might already be stopped
		}
		currentAudioSource = null;
	}
	
	// Clear audio queue completely
		audioQueue.length = 0; // More efficient than reassignment
		audioQueueMap.clear();
		nextExpectedSequence = 0;
	isPlayingAudio = false;
	
	// Clear any pending cleanup timers
	if (audioCleanupTimer) {
		clearTimeout(audioCleanupTimer);
		audioCleanupTimer = null;
	}
	
	log('🔇 Audio interruption complete - immediate silence');
}

function cleanupAudioResources() {
	// Clear any remaining audio sources
	if (currentAudioSource) {
		try {
			currentAudioSource.stop();
			currentAudioSource.disconnect();
		} catch (error) {
			// Ignore errors
		}
		currentAudioSource = null;
	}
	
	// Clear queue
	audioQueue.length = 0;
	audioQueueMap.clear();
	nextExpectedSequence = 0;
	isPlayingAudio = false;
	isInterrupted = false; // Reset interruption flag
	
	// Clear timers
	if (audioCleanupTimer) {
		clearTimeout(audioCleanupTimer);
		audioCleanupTimer = null;
	}
	
	// Reset volume to normal
	if (audioGainNode) {
		audioGainNode.gain.setValueAtTime(1.0, audioContext.currentTime);
	}
	
	// Unmute microphone
	unmuteMicrophone();
	
	log('🧹 Audio resources cleaned up');
}

function resetAudioForNewPlayback() {
	// Reset interruption flag for new TTS
	isInterrupted = false;
	
	// Reset volume to normal
	if (audioGainNode) {
		audioGainNode.gain.setValueAtTime(1.0, audioContext.currentTime);
	}
	
	// Mute microphone during TTS to prevent interference
	muteMicrophone();
	
	log('🔄 Audio reset for new playback');
}

function muteMicrophone() {
	if (micTrack) {
		micTrack.enabled = false;
		log('🔇 Microphone muted during TTS');
	}
}

function unmuteMicrophone() {
	if (micTrack) {
		micTrack.enabled = true;
		log('🎤 Microphone unmuted');
	}
}

async function processAudioQueue() {
	if (isPlayingAudio || audioQueueMap.size === 0) return;
	
	isPlayingAudio = true;
	log(`🎵 Starting sequential audio playback: ${audioQueueMap.size} chunks queued, next expected: ${nextExpectedSequence}`);
	
	// Process queue in order by sequence number
	while (audioQueueMap.size > 0 && isPlayingAudio && !isInterrupted) {
		// Check if we have the next expected sequence
		if (!audioQueueMap.has(nextExpectedSequence)) {
			// Wait a bit for the next chunk to arrive (might be out of order)
			await new Promise(resolve => setTimeout(resolve, 10));
			
			// If still not available after waiting, check if we have any chunks ahead
			if (!audioQueueMap.has(nextExpectedSequence)) {
				const availableSeqs = Array.from(audioQueueMap.keys()).sort((a, b) => a - b);
				if (availableSeqs.length > 0 && availableSeqs[0] > nextExpectedSequence) {
					// We're missing a chunk, skip to the next available one
					log(`⚠️ Missing sequence ${nextExpectedSequence}, skipping to ${availableSeqs[0]}`);
					nextExpectedSequence = availableSeqs[0];
				} else if (availableSeqs.length === 0) {
					// No more chunks available
					break;
				} else {
					// Still waiting for the next chunk
					continue;
				}
			}
		}
		
		// Get and play the next chunk in sequence
		const chunk = audioQueueMap.get(nextExpectedSequence);
		if (!chunk) {
			nextExpectedSequence++;
			continue;
		}
		
		audioQueueMap.delete(nextExpectedSequence);
		nextExpectedSequence++;
		
		// Check interruption before playing each chunk
		if (isInterrupted) {
			log('🔇 Playback interrupted before chunk');
			break;
		}
		
		try {
			log(`🎵 Playing chunk sequence ${chunk.sequence}`);
			await playAudioChunk(chunk.audioData, chunk.sampleRate);
		} catch (error) {
			log('❌ Error playing audio chunk:', error);
			// Continue with next chunk instead of stopping
		}
		
		// Check interruption after each chunk
		if (isInterrupted) {
			log('🔇 Playback interrupted after chunk');
			break;
		}
		
		// Minimal delay to prevent blocking the main thread
		await new Promise(resolve => setTimeout(resolve, 5));
	}
	
	isPlayingAudio = false;
	log(`🎵 Finished sequential audio playback (next expected: ${nextExpectedSequence})`);
	
	// Schedule cleanup after a delay
	if (audioCleanupTimer) {
		clearTimeout(audioCleanupTimer);
	}
	audioCleanupTimer = setTimeout(() => {
		cleanupAudioResources();
	}, 5000); // Clean up after 5 seconds of inactivity
}

function onUnhandledRejection(ev) {
	log('unhandledrejection', ev.reason || 'unknown');
}
window.addEventListener('unhandledrejection', onUnhandledRejection);

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
	cleanupAudioResources();
	if (audioContext && audioContext.state !== 'closed') {
		audioContext.close();
	}
});

// Cleanup on visibility change (when tab becomes hidden)
document.addEventListener('visibilitychange', () => {
	if (document.hidden) {
		// Page is hidden, clean up resources
		cleanupAudioResources();
	}
});

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
		
		// Store microphone track reference for muting
		if (track.kind === 'audio') {
			micTrack = track;
		}
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
			if (msg.event !== 'tts_chunk') {
				console.log('Parsed message:', msg); // Additional debugging
			}
			// Add error handling for each message type
			try {
			
		// Handle new event-based format
		if (msg.event === 'turn_started') {
			transcriptEl.textContent = '';
			transcriptEl.style.fontStyle = 'normal';
			transcriptEl.style.opacity = '1';
			transcriptEl.style.color = '';
			
			// PRIORITY: Interrupt audio playback immediately when user starts speaking
			if (isPlayingAudio || audioQueue.length > 0 || audioQueueMap.size > 0) {
				log('🔇 User started speaking - interrupting audio playback');
				interruptAudioPlayback();
			}
		}
		if (msg.event === 'turn_partial' && msg.text !== undefined) {
			// Show partial results in lighter style
			transcriptEl.textContent = msg.text;
			transcriptEl.style.fontStyle = 'italic';
			transcriptEl.style.opacity = '0.7';
			transcriptEl.style.color = '';
		}
		if (msg.event === 'turn_final' && msg.text !== undefined) {
			// Show final results in normal style (short pause, still listening)
			transcriptEl.textContent = msg.text;
			transcriptEl.style.fontStyle = 'normal';
			transcriptEl.style.opacity = '1';
			transcriptEl.style.color = '';
		}
		if (msg.event === 'turn_complete' && msg.text !== undefined) {
			// Show complete turn in green (long pause, ready for LLM)
			transcriptEl.textContent = msg.text + ' ✓';
			transcriptEl.style.fontStyle = 'normal';
			transcriptEl.style.opacity = '1';
			transcriptEl.style.color = '#4CAF50';  // Green to indicate ready for LLM
			log('🎯 Turn complete - ready for LLM');
		}
		
		// Handle LLM events
		if (msg.event === 'llm_started') {
			// Clear previous LLM response and show loading
			llmResponseEl.textContent = '💭 Thinking...';
			llmResponseEl.style.fontStyle = 'italic';
			llmResponseEl.style.opacity = '0.7';
			log('🤖 LLM started');
		}
		if (msg.event === 'llm_chunk' && msg.text !== undefined) {
			// Append streaming chunks
			const beforeText = llmResponseEl.textContent;
			if (llmResponseEl.textContent === '💭 Thinking...') {
				llmResponseEl.textContent = msg.text;
			} else {
				llmResponseEl.textContent += msg.text;
			}
			const afterText = llmResponseEl.textContent;
			llmResponseEl.style.fontStyle = 'normal';
			llmResponseEl.style.opacity = '1';
			log('🤖 LLM chunk:', msg.text, '| Before:', beforeText, '| After:', afterText);
		}
		if (msg.event === 'llm_complete' && msg.text !== undefined) {
			// Always use the complete response from the server to ensure accuracy
			const beforeText = llmResponseEl.textContent;
			llmResponseEl.textContent = msg.text;
			llmResponseEl.style.fontStyle = 'normal';
			llmResponseEl.style.opacity = '1';
			log('🤖 LLM complete:', msg.text, '| Before:', beforeText, '| After:', llmResponseEl.textContent);
		}
		if (msg.event === 'llm_error') {
			llmResponseEl.textContent = '❌ Error: ' + (msg.error || 'Unknown error');
			llmResponseEl.style.color = '#d32f2f';
			log('❌ LLM error:', msg.error);
		}
		
		// Handle TTS events
		if (msg.event === 'tts_started') {
			log('🎵 TTS synthesis started');
			resetAudioForNewPlayback(); // Reset for new TTS
			// Reset sequence tracking for new TTS session
			audioQueueMap.clear();
			nextExpectedSequence = 0;
		}
		if (msg.event === 'tts_chunk' && msg.audio && msg.sample_rate) {
			const sequence = msg.sequence !== undefined ? msg.sequence : nextExpectedSequence; // Fallback for old format
			
			// Store chunk by sequence number for ordered playback
			audioQueueMap.set(sequence, {
				audioData: msg.audio,
				sampleRate: msg.sample_rate,
				sequence: sequence
			});
			
			// Prevent memory buildup by limiting queue size (drop oldest if needed)
			if (audioQueueMap.size > maxAudioQueueSize) {
				const oldestSeq = Math.min(...audioQueueMap.keys());
				log(`⚠️ Audio queue full (${maxAudioQueueSize}), dropping sequence ${oldestSeq}`);
				audioQueueMap.delete(oldestSeq);
			}
			
			log(`🎵 TTS chunk received: sequence=${sequence}, ${msg.audio.length} bytes at ${msg.sample_rate}Hz (queued: ${audioQueueMap.size})`);
			
			// Process audio queue (will play sentences in order)
			processAudioQueue();
		}
		if (msg.event === 'tts_complete') {
			log('🎵 TTS synthesis complete');
		}
		if (msg.event === 'tts_interrupted') {
			log('🔇 TTS synthesis interrupted by user');
			// Audio interruption is already handled by turn_started event
		}
		if (msg.event === 'tts_error') {
			log('❌ TTS error:', msg.error);
		}
			
			// Backward compatibility: handle old format
			if (msg.partial) {
				transcriptEl.textContent = msg.partial;
				transcriptEl.style.fontStyle = 'italic';
				transcriptEl.style.opacity = '0.7';
			}
			if (msg.final) {
				transcriptEl.textContent = msg.final;
				transcriptEl.style.fontStyle = 'normal';
				transcriptEl.style.opacity = '1';
			}
			
			if (msg.ok) log('server ok');
			if (msg.audio) log('server audio', 'fps', msg.audio.fps, 'rms', msg.audio.rms);
			if (msg.error) log('server error', msg.error);
			} catch (msgError) {
				log('❌ Error processing message:', msgError, '| Message:', msg);
				console.error('Message processing error:', msgError, msg);
			}
		} catch (e) {
			log('❌ JSON parse error:', e, '| Raw data:', ev.data);
			console.error('JSON parse error:', e, ev.data);
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
