String normalizeHandle(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');