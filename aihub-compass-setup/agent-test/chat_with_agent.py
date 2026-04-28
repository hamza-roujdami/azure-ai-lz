"""
Chat with Agent — Interactive chat with a Foundry agent.
"""

import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import AgentReference

load_dotenv()

PROJECT_ENDPOINT = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
AGENT_NAME = os.environ.get("AZURE_AI_AGENT_NAME", "compass-test-agent")


def main():
    print("=" * 60)
    print("Chat with Compass Agent")
    print("=" * 60)
    print(f"\nProject: {PROJECT_ENDPOINT}")
    print(f"Agent:   {AGENT_NAME}")
    print("\nType 'exit' to quit.\n")
    print("-" * 60)

    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)
    openai = client.get_openai_client()

    conversation = openai.conversations.create()
    print(f"Conversation: {conversation.id}\n")

    try:
        while True:
            user_input = input("You: ").strip()
            if not user_input:
                continue
            if user_input.lower() in ("exit", "quit"):
                break

            response = openai.responses.create(
                conversation=conversation.id,
                extra_body={"agent": AgentReference(name=AGENT_NAME).as_dict()},
                input=user_input,
            )
            print(f"\nAgent: {response.output_text}\n")

    except KeyboardInterrupt:
        print("\n\nInterrupted!")
    finally:
        try:
            openai.conversations.delete(conversation_id=conversation.id)
            print(f"\nConversation {conversation.id} deleted.")
        except Exception:
            pass


if __name__ == "__main__":
    main()
