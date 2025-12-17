import asyncio
import os
import sys
import traceback

from beeai_framework.agents.requirement import RequirementAgent
from beeai_framework.backend import ChatModel

async def main():
    agent = RequirementAgent(
        #llm=ChatModel.from_name("ollama:granite3.3"),
        llm = ChatModel.from_name("openai:ibm-granite/granite-4.0-h-small", base_url="http://localhost:8899/v1", api_key="PHD_KEY"),
        role="friendly AI assistant",
        instructions="Be helpful and conversational in all your interactions."
    )

    response = await agent.run("Hello! What can you help me with?")
    print(response.last_message.text)

if __name__ == "__main__":
    asyncio.run(main())
