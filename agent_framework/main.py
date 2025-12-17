import asyncio
import os
import sys
import traceback


# standard imports for the beeai framework 
from beeai_framework.agents.requirement import RequirementAgent
from beeai_framework.backend import ChatModel

# the tools for the agent to be utilized
from beeai_framework.tools.search.wikipedia import WikipediaTool
from beeai_framework.tools.weather import OpenMeteoTool
from beeai_framework.tools.search.duckduckgo import DuckDuckGoSearchTool

async def main():
    agent = RequirementAgent(
        #llm=ChatModel.from_name("ollama:granite3.3"),
        llm = ChatModel.from_name("openai:ibm-granite/granite-4.0-h-small", base_url="http://localhost:8899/v1", api_key="PHD_KEY"),
        role="friendly AI assistant",
        instructions="Be helpful and conversational in all your interactions.",
        tools=[WikipediaTool(), OpenMeteoTool(), DuckDuckGoSearchTool()]
    )

    response = await agent.run("Generate a verbose summary of the city: San Francisco, CA.")
    print(response.last_message.text)

if __name__ == "__main__":
    asyncio.run(main())
