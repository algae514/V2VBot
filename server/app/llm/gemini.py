import os
from typing import Optional, AsyncGenerator
import google.generativeai as genai


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
		
		# Use Gemini 2.0 Flash for fast responses
		model_name = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
		self.model = genai.GenerativeModel(model_name)
		
		# Conversation history
		self.chat = self.model.start_chat(history=[])
		
		print(f"GeminiLLM initialized: model={model_name}")
	
	def is_ready(self) -> bool:
		"""Check if LLM is ready."""
		return self.api_key is not None
	
	async def generate_streaming(self, user_text: str) -> AsyncGenerator[str, None]:
		"""
		Generate streaming response from Gemini.
		
		Args:
			user_text: User's input text
			
		Yields:
			Text chunks as they are generated
		"""
		try:
			# Send message and stream response
			response = self.chat.send_message(user_text, stream=True)
			
			for chunk in response:
				if chunk.text:
					yield chunk.text
					
		except Exception as e:
			print(f"Gemini error: {e}")
			yield f"Error: {str(e)}"
	
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

