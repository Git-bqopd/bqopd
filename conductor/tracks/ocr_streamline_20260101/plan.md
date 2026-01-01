# Plan: Streamline OCR Process

## Phase 1: Backend Optimization & Async Handling
- [x] Task: Analyze existing OCR functions in `functions/main.py` to identify bottlenecks. cd1e096
- [ ] Task: Refactor OCR functions to run asynchronously if they aren't already, using Cloud Tasks or background triggers.
- [ ] Task: Update Firestore schema to support granular status tracking (e.g., `uploading`, `processing`, `review_needed`, `complete`) for each page.
- [ ] Task: Implement status updates in the backend functions to reflect real-time progress in Firestore.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Backend Optimization & Async Handling' (Protocol in workflow.md)

## Phase 2: Curator Workbench UI Updates
- [ ] Task: Create a new `BatchUploadWidget` for the Curator Workbench to allow selecting multiple images.
- [ ] Task: Update `CuratorWorkbenchPage` to integrate the batch upload workflow.
- [ ] Task: Implement a "Job Queue" view in the dashboard to show the status of ongoing OCR tasks.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Curator Workbench UI Updates' (Protocol in workflow.md)

## Phase 3: OCR Review Interface
- [ ] Task: Design and implement a `SideBySideReviewWidget` that displays the original image next to the editable text field.
- [ ] Task: Integrate the review widget into the `FanzineEditorPage` or `CuratorWorkbenchPage`.
- [ ] Task: Add "Re-run OCR" functionality to the review interface with option to adjust simple parameters (if available).
- [ ] Task: Conductor - User Manual Verification 'Phase 3: OCR Review Interface' (Protocol in workflow.md)

## Phase 4: Integration & Polish
- [ ] Task: Connect the frontend batch upload to the backend async functions.
- [ ] Task: thorough testing of the end-to-end workflow (Upload -> Process -> Review -> Publish).
- [ ] Task: Refine error messages and user feedback for failed OCR attempts.
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Integration & Polish' (Protocol in workflow.md)
