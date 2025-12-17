import asyncio
import os
import sys
import traceback
from urllib.parse import quote

import requests

# this is the main agentic framework for phd project 
#
#


# standard imports for the beeai framework
from beeai_framework.agents.requirement import RequirementAgent
from beeai_framework.backend import ChatModel

# the tools for the agent to be utilized
from beeai_framework.tools.search.wikipedia import WikipediaTool
from beeai_framework.tools.weather import OpenMeteoTool
from beeai_framework.tools.search.duckduckgo import DuckDuckGoSearchTool
from beeai_framework.tools import StringToolOutput, Tool, tool

# this is for debugging

# agentic memory formation
from beeai_framework.memory import UnconstrainedMemory

# framwork error exceptions, logging, etc
from beeai_framework.middleware.trajectory import GlobalTrajectoryMiddleware
from beeai_framework.errors import FrameworkError
from beeai_framework.logger import Logger


# establish logger
logger = Logger(__name__)


# defining a tool using the `tool` decorator
@tool
def basic_calculator(expression: str) -> StringToolOutput:
    """
    A calculator tool that performs mathematical operations.

    Args:
        expression: The mathematical expression to evaluate (e.g., "2 + 3 * 4").

    Returns:
        The result of the mathematical expression
    """
    try:
        encoded_expression = quote(expression)
        math_url = f"https://newton.vercel.app/api/v2/simplify/{encoded_expression}"

        response = requests.get(
            math_url,
            headers={"Accept": "application/json"},
        )
        response.raise_for_status()

        return StringToolOutput(json.dumps(response.json()))
    except Exception as e:
        raise RuntimeError(f"Error evaluating expression: {e!s}") from Exception



async def main():
    agent = RequirementAgent(
        #llm=ChatModel.from_name("ollama:granite3.3"),
        llm = ChatModel.from_name("openai:ibm-granite/granite-4.0-h-small", base_url="http://localhost:8899/v1", api_key="PHD_KEY"),
        role="friendly AI assistant",
        instructions="Be helpful and conversational in all your interactions.",
        tools=[WikipediaTool(), OpenMeteoTool(), DuckDuckGoSearchTool(), basic_calculator],
        memory=UnconstrainedMemory() #unconstrained memory for Agent
    )

    response = await agent.run("What is 3 times 27 to the power of 5?").middleware(
        GlobalTrajectoryMiddleware(included=[Tool]))  # Only show tool executions

    print(response.last_message.text)


# main function
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except FrameworkError as e:
        traceback.print_exc()
        sys.exit(e.explain())
