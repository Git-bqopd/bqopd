# Change Behavior of Center Column when Third Column is Open

## User Review Required

> [!IMPORTANT]
> When all three columns are open on desktop, clicking an image in the center column (Column 2 / list reader) will now focus and scroll the third column (Column 3 / bonus panel column) to that page's corresponding card.

## Proposed Changes

### [bqopd_web]

#### [MODIFY] [fanzine_layout.dart](file:///C:/Users/kevla/StudioProjects/bqopd_workspace/apps/bqopd_web/lib/components/fanzine_layout.dart)
- Add a callback `onPageImageTap` (or pass `_handlePageImageTap`) down to `FanzineListRenderer` and `ReaderPageItem`.
- When an image in Column 2 is clicked (and the third column is open), invoke this callback to center Column 3 on the corresponding page card.

#### [MODIFY] [fanzine_list_renderer.dart](file:///C:/Users/kevla/StudioProjects/bqopd_workspace/apps/bqopd_web/lib/components/readers/fanzine_list_renderer.dart)
- Forward `onPageImageTap` callback to each `ReaderPageItem`.

#### [MODIFY] [reader_page_item.dart](file:///C:/Users/kevla/StudioProjects/bqopd_workspace/apps/bqopd_web/lib/components/readers/reader_page_item.dart)
- Remove `pointer-events: none;` from the image element (or wrap it in a clickable container / add click event) so that clicking the image triggers `onPageImageTap(pageIndex)`.

## Verification Plan

### Automated Tests
- Build and test web app compilation.

### Manual Verification
- Open fanzine on desktop in single view with the third column open.
- Click an image in the center column and verify that the third column scrolls/focuses to that page's card.
