# DOE Agentic Workflow

This repository implements the **DOE (Directive-Orchestration-Execution)** Agentic Workflow, a 3-layer architecture designed for reliability and scalability in agentic systems.

## Architecture Overview

The system operates on three distinct layers:

1.  **Directive (Layer 1)**:
    *   **What to do**: Standard Operating Procedures (SOPs) written in Markdown.
    *   **Location**: `directives/`
    *   **Purpose**: Defines goals, inputs, outputs, and edge cases in natural language.

2.  **Orchestration (Layer 2)**:
    *   **Decision Making**: The AI Agent (You).
    *   **Role**: Intelligent routing, reading directives, calling execution tools, handling errors, and updating directives.

3.  **Execution (Layer 3)**:
    *   **Doing the work**: Deterministic Python scripts.
    *   **Location**: `execution/`
    *   **Purpose**: Reliable, testable scripts for API calls, data processing, and file operations.

## Directory Structure

*   `directives/`: Contains the Markdown SOPs.
*   `execution/`: Contains the Python scripts for deterministic tasks.
*   `.tmp/`: (Optional) For intermediate files (not committed).
*   `.env`: (Optional) Environment variables and API keys.

## Operating Principles

1.  **Check for tools first**: Reuse existing scripts in `execution/` before creating new ones.
2.  **Self-anneal**: Fix broken scripts, test them, and update directives with learnings.
3.  **Update directives**: Treat directives as living documents that evolve with the system.
