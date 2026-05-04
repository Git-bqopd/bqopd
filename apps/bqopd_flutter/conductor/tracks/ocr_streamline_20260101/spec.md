# Specification: Streamline OCR Process

## 1. Overview
This track aims to improve the efficiency and usability of the OCR (Optical Character Recognition) workflow within the Curator Dashboard and Curator Workbench. The goal is to make digitizing physical fanzines faster and more accurate for curators.

## 2. Goals
- **Reduce Manual Effort:** Automate steps in the OCR pipeline where possible.
- **Improve Accuracy:** Integrate better error handling and review tools for OCR results.
- **Enhance UI/UX:** Provide a clearer, more intuitive interface for managing OCR tasks in the Workbench.
- **Speed Up Processing:** Optimize the backend functions handling OCR tasks.

## 3. User Stories
- As a **Curator**, I want to upload multiple pages for OCR at once so that I can process whole fanzines quickly.
- As a **Curator**, I want to see a side-by-side view of the original image and the OCR text to easily correct errors.
- As a **Curator**, I want to receive notifications when a long-running OCR job is complete.
- As a **Curator**, I want to easily re-run OCR on specific pages with different settings if the first attempt fails.

## 4. Technical Requirements
- **Frontend (Flutter):**
  - Update `CuratorWorkbench` widget to support batch operations.
  - Implement a split-view editor for text correction.
  - Add progress indicators for background OCR tasks.
- **Backend (Firebase Functions - Python):**
  - Optimize existing OCR functions in `functions/main.py`.
  - Ensure OCR tasks are asynchronous and report progress to Firestore.
- **Database (Firestore):**
  - Update schema to track OCR status per page/fanzine.

## 5. Non-Functional Requirements
- **Performance:** OCR results should be available for review within reasonable time limits (e.g., < 10 seconds per page).
- **Usability:** The UI must remain responsive during batch uploads.
