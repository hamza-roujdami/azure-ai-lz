"""
Test Connection — Verify APIM connection is configured in Foundry.
"""

import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

load_dotenv()

PROJECT_ENDPOINT = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
CONNECTION_NAME = os.environ.get("AZURE_AI_CONNECTION_NAME", "compass-apim")
MODEL_NAME = os.environ.get("AZURE_AI_MODEL_NAME", "gpt-5.1")


def main():
    print("=" * 60)
    print("Testing Foundry → APIM → Compass Connection")
    print("=" * 60)
    print(f"\nProject:    {PROJECT_ENDPOINT}")
    print(f"Connection: {CONNECTION_NAME}")
    print(f"Model:      {MODEL_NAME}")
    print()

    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=credential)

    # List connections
    print("Connections:")
    print("-" * 40)
    found = False
    for conn in client.connections.list():
        marker = "→" if conn.name == CONNECTION_NAME else " "
        print(f"  {marker} {conn.name}")
        if hasattr(conn, "properties"):
            category = getattr(conn.properties, "category", "Unknown")
            target = getattr(conn.properties, "target", "N/A")
            print(f"    Category: {category}")
            print(f"    Target:   {target}")
        print()
        if conn.name == CONNECTION_NAME:
            found = True

    if found:
        print(f"✅ Connection '{CONNECTION_NAME}' found!")
    else:
        print(f"❌ Connection '{CONNECTION_NAME}' NOT found.")
        print("   Run foundry-connection.bicep first (Step 2 in README).")
        return

    # Quick inference test
    print(f"\nTesting inference with model '{MODEL_NAME}'...")
    openai = client.inference.get_chat_completions_client()
    response = openai.complete(
        model=f"{CONNECTION_NAME}/{MODEL_NAME}",
        messages=[{"role": "user", "content": "Say hello in one word"}],
        max_tokens=10,
    )
    print(f"Response: {response.choices[0].message.content}")
    print("\n✅ Connection works!")


if __name__ == "__main__":
    main()
