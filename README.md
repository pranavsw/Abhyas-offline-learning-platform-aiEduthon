# NCERT AI Tutor: Offline On-Device RAG Application

A sophisticated educational application built with Flutter that brings a personal AI tutor to mobile devices. It functions **completely offline** (after initial model download) by leveraging **On-Device RAG (Retrieval Augmented Generation)**.

The app combines Google's **Gemma3-1B-IT** with a vector database to answer student questions, generate quizzes, and summarize chapters from NCERT Class 9 Textbooks (English & Science) without sending data to the cloud.

## 🚀 Features

1.  **Subject-Aware Chat Tutor:** Ask questions about specific chapters (e.g., "Why did Margie hate school?"). The AI retrieves the exact paragraph from the book and answers based _only_ on that context.
2.  **Generative Quiz Mode:** Select a chapter, and the AI generates unique multiple-choice questions based on random topics from that chapter.
3.  **Smart Syllabus & Summarizer:** Read the full textbook and use a "Map-Reduce" AI strategy to summarize long chapters into bullet points without crashing device memory.
4.  **Dual-Engine Architecture:** Uses TFLite for fast semantic search (Retrieval) and MediaPipe GenAI for intelligent reasoning (Generation).

## 🛠️ Setup & Installation

### 1\. Prerequisites

*   **Flutter SDK** (3.19 or higher)
*   **Android Toolchain** (Min SDK 26+)
*   **Hugging Face Token** (Access to Gemma models required)

### 2\. Asset Preparation

Before running the app, ensuring the assets/ folder contains the "Brain" and "Memory" of the AI is critical.

**Required File Structure:**

project\_root/  
├── assets/  
│ ├── class9\_english.json # Raw Text: English Textbook  
│ ├── class9\_science.json # Raw Text: Science Textbook  
│ ├── class9\_complete.db # Vector DB: Generated via preprocess.py  
│ ├── mobile\_embedding.tflite # Embedder: all-MiniLM-L6-v2 (Quantized)  
│ └── vocab.txt # Tokenizer: Vocabulary file for BERT  

### 3\. Configuration

Open lib/main.dart and update your Hugging Face token:

const String kHuggingFaceToken = "YOUR\_HF\_TOKEN\_HERE";  

### 4\. Running the App

flutter pub get  
flutter run  

_Note: First run will download the ~1.3GB Gemma model. Subsequent runs are instant._

## 🧠 The RAG Pipeline Overview

This app implements a full **Retrieval Augmented Generation** pipeline directly on the mobile device.

1.  **User Query:** Student asks "What is Evaporation?"
2.  **Tokenization:** The input is converted into IDs using vocab.txt.
3.  **Embedding:** mobile\_embedding.tflite converts IDs into a vector (384 floats).
4.  **Vector Search:** RagService scans class9\_complete.db using Cosine Similarity to find the 3 most relevant textbook paragraphs.
5.  **Context Injection:** The retrieved paragraphs + the user question are combined into a prompt.
6.  **Generation:** **Gemma 2B** (running via MediaPipe) reads the prompt and generates the answer.

## 🧩 Major Components

### 1\. RagService (The Search Engine)

This class is the bridge between the user's query and the textbook database.

*   **Technology:** sqflite + tflite\_flutter.
*   **Function:** It runs the embedding model locally. It performs the dot-product calculation to find the nearest text chunks.
*   **Smart Feature:** It supports **Subject Filtering**. If the user selects "Science", it dynamically modifies the SQL query to only search chunks tagged with book\_source = 'Science', preventing cross-subject hallucinations.

### 2\. BookService (The Content Manager)

This class manages the raw structure of the textbooks.

*   **Technology:** Dart JSON decoding.
*   **Function:** It loads the full hierarchy of the books (Chapters -> Topics -> Content).
*   **Smart Feature:** **Random Context Sampling**. For the Quiz mode, it doesn't just pick the "start" of a chapter. It randomly samples 5 topics from the JSON to ensure the quiz covers different parts of the lesson every time.

### 3\. FlutterGemma (The Brain)

This is the interface to the Large Language Model.

*   **Technology:** MediaPipe GenAI (Google).
*   **Model:** gemma-2b-it-cpu-int4 (Instruction Tuned, 4-bit Quantized).
*   **Optimization:** We force the **CPU Backend** (PreferredBackend.cpu) to ensure maximum compatibility across varied Android devices and Emulators, preventing GPU driver crashes.

### 4\. JsonCleaner (The Guardrail)

Small models (2B parameters) are prone to formatting errors. They often add conversational filler like "Here is your JSON:".

*   **Function:** This utility uses regex to strip away Markdown backticks and extracts only the valid {...} JSON object from the AI's response, preventing app crashes during Quiz generation.

## ⚙️ Technical Deep Dives

### Preprocessing (Python Phase)

Before the app runs, the data was prepared using preprocess.py.

1.  **Chunking:** Text was split into 500-character chunks using RecursiveCharacterTextSplitter.
2.  **Enrichment:** Metadata (Chapter Name, Topic Name) was prepended to every chunk.
3.  **Vectorization:** sentence-transformers/all-MiniLM-L6-v2 created the embeddings.
4.  **Storage:** Data was saved to SQLite for mobile access.

### Robust Session Management

One of the biggest challenges with on-device LLMs is **Context Window Overflow (OUT\_OF\_RANGE)**.

*   **Problem:** If a chat session is kept alive too long, the history fills the 1024 token limit, causing the app to freeze.
*   **Our Solution:** **One-Shot Sessions**.
    *   For every single query (Chat or Quiz), we create a new InferenceChat().
    *   We send the prompt.
    *   We receive the stream.
    *   We let the session object die (Garbage Collection).
    *   This guarantees the model always starts with 0 context usage for every new interaction, ensuring 100% stability.

### Sequential Summarization

To summarize massive chapters (5000+ words) on a small RAM device:

1.  The app splits the full text into 1000-character blocks.
2.  It loops through them one by one.
3.  It asks the AI to "Summarize this block in 1 bullet point".
4.  It aggregates the results into a final list.  
    This "Streaming Map-Reduce" approach allows a small 2B model to process infinite-length documents without running out of memory.
