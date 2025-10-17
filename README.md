# Scria.ai: AI Agent for Accessible Formal Verification of Smart Contracts

> **Status: Actively Developing Core: Vector Database Ingestion & LLM Prompt Engineering**

Scria.ai is an innovative AI-powered agent designed to **democratize formal verification (FV)** in smart contract development. We eliminate the need for developers to write complex security properties in specialized formal languages (like Certora's CVL) by leveraging AI and a powerful knowledge base of mathematically-proven contracts.

## The Problem Scria.ai Solves

Formal verification is the ultimate standard for smart contract security, as it **mathematically proves** the absence of bugs. However, its adoption is hindered by:
1.  **Complexity:** Writing correct security properties requires deep, specialized knowledge of formal logic and verification languages.
2.  **Context Gap:** Developers often lack the security expertise to determine *what* critical properties they should be testing.

**Scria.ai's Solution:** We make the power of formal verification accessible. Users simply describe security goals in **plain English**. Scria automatically handles the entire lifecycle: **property generation**, **testing**, and the creation of a clear, actionable **audit report**.

## Core Technology and Features

Scria.ai is engineered around a cutting-edge **Retrieval-Augmented Generation (RAG)** pipeline, which seamlessly combines high-precision semantic search with a Large Language Model (LLM).

### 1. The Vector Database (The Knowledge Base)

* **Function:** Stores the semantic "fingerprints" of battle-tested smart contracts and their corresponding mathematically-proven properties.
* **Data:** A curated dataset of OpenZeppelin contracts, Certora Examples, and other formally verified code, along with their detailed specifications (`.spec` files).
* **Technology:** Uses **code-specific embedding models** (e.g., CodeBERT) to convert code into high-dimensional vectors. This enables **semantic search**—finding contracts that are functionally similar, even if their code differs structurally.

### 2. The LLM Agent (The Property Generator & Auditor)

* **Function:** Translates user intent into formal, executable properties and processes test results into a human-readable audit report.
* **Input:** The new smart contract code, the user's plain English property description, and the top **$N$ most similar property templates** retrieved from the Vector Database.
* **Output:** Generates new, customized properties in a formal verification language (e.g., CVL) or a property-based testing format (e.g., Echidna), ready for verification.

### 3. Core Feature Flow

1.  **Input:** User provides a new Solidity contract and a plain English property (e.g., "The `transfer` function must never allow a negative balance.").
2.  **Retrieve:** Scria.ai queries the Vector Database, retrieving the most relevant property templates from similar existing contracts.
3.  **Generate:** The LLM uses the new contract, the user's text, and the retrieved templates as context to generate a robust, formal property.
4.  **Audit:** The generated property is passed to a testing engine. Scria then processes the results (pass/fail/counter-example) into a structured **Audit Report**.

## Project Roadmap

| Phase | Goal | Status |
| :--- | :--- | :--- |
| **Phase 1: Data Ingestion** | Build the foundational Vector Database and data processing pipeline. | **In Progress 🚧** |
| | - Curate and clean the initial dataset (OpenZeppelin, Certora Examples). | |
| | - Select and implement a code-specific embedding model. | |
| | - Index all contracts and properties into the vector store (e.g., Faiss/Pinecone). | |
| **Phase 2: RAG Pipeline** | Develop the core retrieval and generation engine. | **Planned** |
| | - Implement semantic search to retrieve top-N similar properties. | |
| | - Design and refine the core LLM prompt for property generation (CVL/Echidna format). | |
| **Phase 3: Integration & Demo** | Create a functional prototype and audit reporting interface. | **Planned** |
| | - Build a simple command-line interface (CLI) or web demo. | |
| | - Integrate with a testing engine (e.g., Echidna or Certora Prover stub) and generate the final audit report. | |

## Getting Started

This project is currently focused on backend and core logic development.

To contribute or follow along with the project's progress:

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/HarshvardhanPrajapati/Scria.git](https://github.com/HarshvardhanPrajapati/Scria.git)
    cd Scria
    ```
2.  **Setup Environment:**
    Install Node.js dependencies (assuming the front-end/service layer is Node-based). Python dependencies for the AI core will be handled separately.

    ```bash
    # Install dependencies
    npm install
    ```
3.  **Check Progress:** The initial data and parsing logic can be reviewed in the **`ContractsAndProperties/`** directory and the **`file_parser.js`** script.

## Contribution

I welcome contributions! If you are interested in:
* Curating more high-quality smart contract-property pairs.
* Optimizing code embedding models.
* Improving prompt engineering for formal logic accuracy.

Please open an issue or submit a pull request!

## License

This project is licensed under the MIT License.