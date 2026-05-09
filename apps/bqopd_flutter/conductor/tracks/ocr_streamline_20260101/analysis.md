# Analysis of Existing OCR Functions

## Findings from functions/main.py

1.  **Architecture**:
    - Uses `on_document_written` triggers for state management (`fanzine_traffic_manager`).
    - Uses `on_document_written` for individual page OCR (`ocr_worker`).
    - Uses HTTP Callables for manual triggers (`trigger_batch_ocr`).

2.  **Bottlenecks**:
    - `_do_pdf_ingest` runs synchronously inside `fanzine_traffic_manager` (540s timeout). Large PDFs will fail.
    - `ocr_worker` uses `gemini-3-flash-preview`. Concurrency is managed by Firestore/Cloud Functions scaling.

3.  **Status Tracking**:
    - Pages have `status`: `ready`, `queued`, `ocr_complete`, `error`.
    - Fanzines have `processingStatus`: `needs_ingest`, `extracting_images`, `processing_ocr`, `ready_for_agg`, `aggregating`, `complete`.

4.  **Missing for "Streamline" Track**:
    - **Direct Image Upload**: Current flow assumes PDF source. Phase 2 requires "Batch Upload" of images. We need a way to handle direct image uploads and create page docs without a PDF.
    - **Review State**: No explicit `review_needed` state. `ocr_complete` implies it's done. We need to distinguish between "OCR finished" and "Curator reviewed".
    - **Granular Progress**: The frontend needs to know how many pages are done vs total.

## Recommendations for Phase 1 Implementation

1.  **Refactor**: Keep `ocr_worker` as is but update the success status to `review_needed` (or add a `reviewStatus` field).
2.  **Schema**: Add `reviewStatus` to page documents.
3.  **New Functionality**: We might need a Callable or Trigger for "Batch Image Ingest" to support the frontend requirement. (This might be in Phase 2 or Phase 1). The Plan Phase 1 says "Update Firestore schema...".
