"""
Create Agent — Creates a Foundry agent using Compass models via APIM.
"""

import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition

load_dotenv()

PROJECT_ENDPOINT = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
CONNECTION_NAME = os.environ.get("AZURE_AI_CONNECTION_NAME", "compass-apim")
MODEL_NAME = os.environ.get("AZURE_AI_MODEL_NAME", "gpt-5.1")
AGENT_NAME = os.environ.get("AZURE_AI_AGENT_NAME", "compass-test-agent")

AGENT_INSTRUCTIONS = """You are a helpful assistant powered by Core42 Compass via APIM.
Be concise and helpful in your responses."""


def main():
    print("=" * 60)
    print("Creating Foundry Agent")
    print("=" * 60)
    print(f"\nProject: {PROJECT_ENDPOINT}")
    print(f"Model:   {CONNECTION_NAME}/{MODEL_NAME}")
    print(f"Agent:   {AGENT_NAME}")
    print()

    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)

    print("Creating agent...")
    agent = client.agents.create_version(
        agent_name=AGENT_NAME,
        definition=PromptAgentDefinition(
            model=f"{CONNECTION_NAME}/{MODEL_NAME}",
            instructions=AGENT_INSTRUCTIONS,
        ),
    )

    print(f"\n✅ Agent created!")
    print(f"   Name:    {agent.name}")
    print(f"   Version: {agent.version}")
    print()
    print("Next: python chat_with_agent.py")


if __name__ == "__main__":
    main()
