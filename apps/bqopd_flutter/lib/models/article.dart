import 'package:cloud_firestore/cloud_firestore.dart';

enum ArticleBlockType { text, image, link, unknown }

abstract class ArticleBlock {
  final ArticleBlockType type;
  ArticleBlock(this.type);

  Map<String, dynamic> toMap();

  static ArticleBlock fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String?;
    switch (typeStr) {
      case 'text':
        return TextBlock.fromMap(map);
      case 'image':
        return ImageBlock.fromMap(map);
      case 'link':
        return LinkBlock.fromMap(map);
      default:
        return UnknownBlock();
    }
  }
}

class TextBlock extends ArticleBlock {
  final String content;
  TextBlock({required this.content}) : super(ArticleBlockType.text);

  @override
  Map<String, dynamic> toMap() => {'type': 'text', 'content': content};

  factory TextBlock.fromMap(Map<String, dynamic> map) {
    return TextBlock(content: map['content'] ?? '');
  }
}

class ImageBlock extends ArticleBlock {
  final String imageUrl;
  final String? caption;
  ImageBlock({required this.imageUrl, this.caption})
      : super(ArticleBlockType.image);

  @override
  Map<String, dynamic> toMap() =>
      {'type': 'image', 'imageUrl': imageUrl, 'caption': caption};

  factory ImageBlock.fromMap(Map<String, dynamic> map) {
    return ImageBlock(
      imageUrl: map['imageUrl'] ?? '',
      caption: map['caption'],
    );
  }
}

class LinkBlock extends ArticleBlock {
  final String url;
  final String title;
  LinkBlock({required this.url, required this.title})
      : super(ArticleBlockType.link);

  @override
  Map<String, dynamic> toMap() => {'type': 'link', 'url': url, 'title': title};

  factory LinkBlock.fromMap(Map<String, dynamic> map) {
    return LinkBlock(
      url: map['url'] ?? '',
      title: map['title'] ?? '',
    );
  }
}

class UnknownBlock extends ArticleBlock {
  UnknownBlock() : super(ArticleBlockType.unknown);
  @override
  Map<String, dynamic> toMap() => {'type': 'unknown'};
}

class Article {
  final String id;
  final String title;
  final String gridCoverImage; // 5:8 aspect ratio
  final List<ArticleBlock> blocks;
  final DateTime createdAt;

  Article({
    required this.id,
    required this.title,
    required this.gridCoverImage,
    required this.blocks,
    required this.createdAt,
  });

  factory Article.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final blocksList = (data['blocks'] as List<dynamic>?) ?? [];

    return Article(
      id: doc.id,
      title: data['title'] ?? '',
      gridCoverImage: data['gridCoverImage'] ?? '',
      blocks: blocksList
          .map((b) => ArticleBlock.fromMap(b as Map<String, dynamic>))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'gridCoverImage': gridCoverImage,
      'blocks': blocks.map((b) => b.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
