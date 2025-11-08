import os
from typing import Optional, AsyncGenerator
import time
import logging
import asyncio
import google.generativeai as genai

logger = logging.getLogger(__name__)


class GeminiLLM:
	def __init__(self, api_key: Optional[str] = None):
		"""
		Initialize Gemini LLM.
		
		Args:
			api_key: Gemini API key (defaults to GEMINI_API_KEY env var)
		"""
		self.api_key = api_key or os.getenv("GEMINI_API_KEY")
		if not self.api_key:
			raise ValueError("GEMINI_API_KEY not provided")
		
		# Configure Gemini
		genai.configure(api_key=self.api_key)
		
		# Use Gemini 1.5 Flash for faster responses (optimized for speed)
		model_name = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")
		self.model = genai.GenerativeModel(model_name)
		
		# Conversation history
		self.chat = self.model.start_chat(history=[])
		
		print(f"GeminiLLM initialized: model={model_name}")
	
	def is_ready(self) -> bool:
		"""Check if LLM is ready."""
		return self.api_key is not None
	
	async def generate_streaming(self, user_text: str) -> AsyncGenerator[str, None]:
		"""
		Generate streaming response from Gemini with retry logic for rate limits.
		
		Args:
			user_text: User's input text
			
		Yields:
			Text chunks as they are generated
		"""
		gen_start = time.time()
		max_retries = 3
		retry_count = 0
		
		while retry_count < max_retries:
			try:
				# Send message and stream response
				api_start = time.time()
				response = self.chat.send_message(user_text, stream=True)
				api_latency = (time.time() - api_start) * 1000
				
				if retry_count > 0:
					logger.info(f"[LATENCY] LLM API call (retry {retry_count}): {api_latency:.2f}ms")
				else:
					logger.info(f"[LATENCY] LLM API call: {api_latency:.2f}ms")
				
				chunk_count = 0
				first_chunk_time = None
				for chunk in response:
					if chunk.text:
						if first_chunk_time is None:
							first_chunk_time = time.time()
							ttfb = (first_chunk_time - gen_start) * 1000
							logger.info(f"[LATENCY] LLM first token (TTFB): {ttfb:.2f}ms")
						
						chunk_count += 1
						yield chunk.text
				
				total_latency = (time.time() - gen_start) * 1000
				logger.info(f"[LATENCY] LLM streaming: api_call={api_latency:.2f}ms, chunks={chunk_count}, TOTAL={total_latency:.2f}ms")
				return  # Success, exit retry loop
					
			except Exception as e:
				error_str = str(e)
				is_rate_limit = "429" in error_str or "Resource exhausted" in error_str
				
				if is_rate_limit and retry_count < max_retries - 1:
					retry_count += 1
					wait_time = 2 ** retry_count  # Exponential backoff: 2s, 4s, 8s
					total_latency = (time.time() - gen_start) * 1000
					logger.warning(f"[LATENCY] LLM rate limit (attempt {retry_count}/{max_retries}), waiting {wait_time}s before retry (elapsed: {total_latency:.2f}ms)")
					print(f"[LLM] Rate limit hit, retrying in {wait_time}s (attempt {retry_count}/{max_retries})...")
					await asyncio.sleep(wait_time)
					continue  # Retry
				else:
					# Not a rate limit, or max retries reached
					total_latency = (time.time() - gen_start) * 1000
					print(f"Gemini error: {e}")
					if is_rate_limit:
						logger.error(f"[LATENCY] LLM rate limit error after {max_retries} retries ({total_latency:.2f}ms): {e}")
					else:
						logger.error(f"[LATENCY] LLM error after {total_latency:.2f}ms: {e}")
					yield f"Error: {str(e)}"
					return  # Exit on non-retryable error or max retries
	
	async def generate(self, user_text: str) -> str:
		"""
		Generate complete response from Gemini (non-streaming).
		
		Args:
			user_text: User's input text
			
		Returns:
			Complete response text
		"""
		try:
			response = self.chat.send_message(user_text)
			return response.text
		except Exception as e:
			print(f"Gemini error: {e}")
			return f"Error: {str(e)}"
	
	def reset_conversation(self):
		"""Reset conversation history."""
		self.chat = self.model.start_chat(history=[])
		print("Conversation history reset")

