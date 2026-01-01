import unittest
from unittest.mock import MagicMock, patch
import sys
import os

# Mock the external dependencies BEFORE importing main
sys.modules['firebase_admin'] = MagicMock()
sys.modules['firebase_admin.firestore'] = MagicMock()
sys.modules['firebase_admin.storage'] = MagicMock()
sys.modules['firebase_functions'] = MagicMock()
sys.modules['firebase_functions.params'] = MagicMock()
sys.modules['firebase_functions.firestore_fn'] = MagicMock()
sys.modules['google'] = MagicMock()
sys.modules['google.genai'] = MagicMock()

# Configure the decorator to pass through the function
# Because main.py uses @firestore_fn.on_document_written(...)
# This call returns a decorator, which is then called with the function.
# So on_document_written(...) must return a callable (the decorator).
# That callable must return the function (x).
mock_firestore_fn = sys.modules['firebase_functions'].firestore_fn
mock_firestore_fn.on_document_written.return_value = lambda x: x
mock_firestore_fn.on_document_created.return_value = lambda x: x # For others if needed

from main import ocr_worker, fanzine_traffic_manager

class TestOCRWorker(unittest.TestCase):
    @patch('main.firestore')
    def test_traffic_manager_moves_to_review_needed(self, mock_firestore):
        # Setup Event
        mock_event = MagicMock()
        mock_event.data.after.exists = True
        mock_event.data.after.to_dict.return_value = {
            'processingStatus': 'processing_ocr',
            'sourceFile': 'test.pdf'
        }
        mock_event.params = {'fanzineId': 'f1'}
        
        # Mock DB
        mock_db = MagicMock()
        mock_firestore.client.return_value = mock_db
        mock_fref = MagicMock()
        mock_db.collection.return_value.document.return_value = mock_fref
        
        # Mock Pages Query (No pending pages)
        mock_pages_ref = MagicMock()
        mock_fref.collection.return_value = mock_pages_ref
        mock_pages_ref.where.return_value.limit.return_value.stream.return_value = [] # Empty list = no pending
        
        # Execute
        fanzine_traffic_manager(mock_event)
        
        # Assert
        # Current code sets 'ready_for_agg'. We want 'review_needed'.
        mock_fref.update.assert_called_with({'processingStatus': 'review_needed'})

    @patch('main.firestore')
    @patch('main.storage')
    @patch('main.genai')
    def test_ocr_worker_success_sets_review_needed(self, mock_genai, mock_storage, mock_firestore):
        # Setup Mocks
        mock_event = MagicMock()
        mock_snapshot = MagicMock()
        mock_snapshot.exists = True
        mock_snapshot.to_dict.return_value = {
            'status': 'queued',
            'storagePath': 'path/to/image.jpg'
        }
        # Mock Page Reference
        mock_page_ref = MagicMock()
        mock_snapshot.reference = mock_page_ref
        
        mock_event.data.after = mock_snapshot
        mock_event.params = {'fanzineId': 'f1', 'pageId': 'p1'}


        # Mock Storage
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_storage.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        mock_blob.download_as_bytes.return_value = b'fake_image_bytes'

        # Mock GenAI
        mock_client = MagicMock()
        mock_genai.Client.return_value = mock_client
        mock_response = MagicMock()
        mock_response.text = '{"text": "Sample Text", "entities": ["Entity1"]}'
        mock_client.models.generate_content.return_value = mock_response

        # Execute
        ocr_worker(mock_event)

        # Assert
        print(f"Update called? {mock_page_ref.update.called}")
        print(f"Call args: {mock_page_ref.update.call_args_list}")
        
        # We expect the update to verify 'status' is 'review_needed'
        # Currently the code sets it to 'ocr_complete', so this should FAIL
        args, _ = mock_page_ref.update.call_args
        update_dict = args[0]
        self.assertEqual(update_dict['status'], 'review_needed')

if __name__ == '__main__':
    unittest.main()
