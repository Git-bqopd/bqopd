import 'dart:math' as math;
import 'package:equatable/equatable.dart';
import '../models/fanzine_page.dart';
import '../models/publisher_models.dart';
import '../utils/text_html_renderer.dart';

/// Represents a recipient's engagement & personalization context used by
/// [FanzineBlueprintEngine] to score and assemble a hypothetical 24-page fanzine.
class RecipientFeedContext extends Equatable {
  final String userId;
  final String displayName;
  final String? username;
  final String city;
  final String state;
  final String zipCode;
  final bool playsTerminalGame;
  final Set<String> followedCreatorIds;
  final Set<String> likedHashtags;
  final Set<String> seenItemIds;

  const RecipientFeedContext({
    required this.userId,
    required this.displayName,
    this.username,
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.playsTerminalGame = false,
    this.followedCreatorIds = const {},
    this.likedHashtags = const {},
    this.seenItemIds = const {},
  });

  String get locationLabel {
    final parts = [
      if (city.trim().isNotEmpty) city.trim(),
      if (state.trim().isNotEmpty) state.trim(),
      if (zipCode.trim().isNotEmpty) zipCode.trim(),
    ];
    return parts.isEmpty ? 'Global / Unspecified Carrier Route' : parts.join(', ');
  }

  /// Builds a deterministic [RecipientFeedContext] from a profile map or [CirculationRecipient].
  factory RecipientFeedContext.fromProfileMap(Map<String, dynamic> map) {
    final String uid = (map['uid'] ?? map['id'] ?? 'guest').toString();
    final String name =
        (map['displayName'] ?? map['username'] ?? 'Reader').toString();
    final String? handle = map['username']?.toString();
    final String city = (map['city'] ?? '').toString();
    final String state = (map['state'] ?? '').toString();
    final String zip = (map['zipCode'] ?? '').toString();

    // Deterministically derive sample engagement signals when raw activity sets aren't loaded yet
    final int hash = uid.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    final bool playsTerminal = map['playsTerminal'] == true ||
        map['Editor'] == true ||
        (hash % 2 == 0);

    final rawTags = map['tags'] ?? map['interests'];
    final Set<String> tags = rawTags is Iterable
        ? rawTags.map((e) => e.toString().toLowerCase()).toSet()
        : _defaultHashtagsForHash(hash);

    return RecipientFeedContext(
      userId: uid,
      displayName: name,
      username: handle,
      city: city,
      state: state,
      zipCode: zip,
      playsTerminalGame: playsTerminal,
      likedHashtags: tags,
    );
  }

  static Set<String> _defaultHashtagsForHash(int hash) {
    const pool = [
      'scifi',
      'weird-tales',
      'correspondence',
      'linotype',
      'comics',
      'Reviews',
      'conventions',
      'combat-terminal',
      'astronomy',
      'pulp-art',
    ];
    return {
      pool[hash % pool.length].toLowerCase(),
      pool[(hash ~/ 3) % pool.length].toLowerCase(),
      pool[(hash ~/ 7) % pool.length].toLowerCase(),
    };
  }

  @override
  List<Object?> get props => [
    userId,
    displayName,
    username,
    city,
    state,
    zipCode,
    playsTerminalGame,
    followedCreatorIds,
    likedHashtags,
    seenItemIds,
  ];
}

/// Candidate item from the Maker UGC / Ad / Programmatic pool that can occupy 1 or more pages.
class BlueprintCandidateItem extends Equatable {
  final String id;
  final String title;
  final String creatorName;
  final String creatorId;
  final BlueprintSlotSource sourceType;
  final int pageSpan; // e.g. 1 for single page, 2 for two-page spread
  final String sidePreference; // 'either', 'left' (even page), 'right' (odd page)
  final List<String> hashtags;
  final String? city;
  final String? state;
  final int likeCount;
  final int commentCount;
  final String? imageUrl;
  final String? gridUrl;
  final String? listUrl;
  final String bodyMarkdown;

  const BlueprintCandidateItem({
    required this.id,
    required this.title,
    required this.creatorName,
    this.creatorId = '',
    required this.sourceType,
    this.pageSpan = 1,
    this.sidePreference = 'either',
    this.hashtags = const [],
    this.city,
    this.state,
    this.likeCount = 0,
    this.commentCount = 0,
    this.imageUrl,
    this.gridUrl,
    this.listUrl,
    this.bodyMarkdown = '',
  });

  @override
  List<Object?> get props => [
    id,
    title,
    creatorName,
    creatorId,
    sourceType,
    pageSpan,
    sidePreference,
    hashtags,
    city,
    state,
    likeCount,
    commentCount,
    imageUrl,
  ];
}

/// Pure-Dart 2-stage scoring and 24-page pagination engine for `/publisher`.
///
/// 1. Scores candidate UGC, Local, Terminal, and Ad items for a target [RecipientFeedContext]
///    ("First 24 posts on Instagram" feed ranker).
/// 2. Packs them into a 24-page saddle-stitch blueprint (`Pages 1..24`), respecting
///    `left`/`right` spread alignment and automatically backfilling 1-page pagination gaps
///    with Ads or Filler pages.
class FanzineBlueprintEngine {
  const FanzineBlueprintEngine._();

  /// Computes a personalization score for [item] given [recipient].
  static double scoreCandidate(
    BlueprintCandidateItem item,
    RecipientFeedContext? recipient,
  ) {
    double score = 10.0;

    // Engagement momentum (log-scaled likes + 2x comments)
    final engagement = item.likeCount + (item.commentCount * 2);
    if (engagement > 0) {
      score += math.log(1 + engagement) * 4.5;
    }

    if (recipient == null) return score;

    // 1. Followed creator boost
    if (item.creatorId.isNotEmpty &&
        recipient.followedCreatorIds.contains(item.creatorId)) {
      score += 35.0;
    }

    // 2. Hashtag / interest affinity overlap
    int tagMatches = 0;
    for (final tag in item.hashtags) {
      if (recipient.likedHashtags.contains(tag.toLowerCase())) {
        tagMatches++;
      }
    }
    score += tagMatches * 14.0;

    // 3. Geographic / Carrier-route proximity boost
    if (recipient.city.trim().isNotEmpty &&
        item.city != null &&
        item.city!.toLowerCase() == recipient.city.trim().toLowerCase()) {
      score += 28.0;
    } else if (recipient.state.trim().isNotEmpty &&
        item.state != null &&
        item.state!.toLowerCase() == recipient.state.trim().toLowerCase()) {
      score += 15.0;
    }

    // Deterministic per-user tie-breaker so different users see distinct feed mixes
    final tieSeed = (recipient.userId.hashCode ^ item.id.hashCode).abs() % 100;
    score += (tieSeed / 20.0);

    return score;
  }

  /// Resolves which [BlueprintSlotSource] applies to [pageNumber] after evaluating
  /// any conditional rule against [recipient].
  static BlueprintSlotSource resolveSlotSource({
    required BlueprintSlotRule rule,
    required RecipientFeedContext? recipient,
  }) {
    if (rule.primarySource == BlueprintSlotSource.terminalTurn ||
        rule.condition == 'plays_terminal') {
      final playsTerminal = recipient?.playsTerminalGame ?? false;
      return playsTerminal ? rule.primarySource : rule.fallbackSource;
    }
    if (rule.condition == 'has_local_pool') {
      final hasLocation = recipient != null &&
          (recipient.city.trim().isNotEmpty ||
              recipient.state.trim().isNotEmpty ||
              recipient.zipCode.trim().isNotEmpty);
      return hasLocation ? rule.primarySource : rule.fallbackSource;
    }
    return rule.primarySource;
  }

  /// Assembles a complete 24-page hypothetical fanzine (`List<FanzinePage>`) for [blueprint]
  /// personalized to [recipient] (or the default editorial baseline when [recipient] is null).
  static List<FanzinePage> assembleHypotheticalPages({
    required ScheduledFanzine blueprint,
    int slotIndex = 1,
    RecipientFeedContext? recipient,
    List<BlueprintCandidateItem> customPool = const [],
  }) {
    final rules = blueprint.effectiveRules(slotIndex: slotIndex);
    final pool = customPool.isNotEmpty
        ? List<BlueprintCandidateItem>.from(customPool)
        : _buildDefaultCandidatePool(blueprint, recipient);

    final Set<String> usedItemIds = {
      if (recipient != null) ...recipient.seenItemIds,
    };

    final Map<int, FanzinePage> assembledByPage = {};

    BlueprintSlotRule ruleForPage(int p) {
      for (final r in rules) {
        if (r.containsPage(p)) return r;
      }
      return BlueprintSlotRule(
        startPage: p,
        endPage: p,
        primarySource: BlueprintSlotSource.globalUgc,
      );
    }

    int pageNum = 1;
    while (pageNum <= 24) {
      if (assembledByPage.containsKey(pageNum)) {
        pageNum++;
        continue;
      }

      final rule = ruleForPage(pageNum);
      final effectiveSource = resolveSlotSource(
        rule: rule,
        recipient: recipient,
      );
      final bool wasFallback = effectiveSource != rule.primarySource;
      final String side = (pageNum % 2 == 0) ? 'left' : 'right';

      // Special fixed handling for Page 1 (Front Cover) and Page 2 (Indicia)
      if (pageNum == 1 && effectiveSource == BlueprintSlotSource.coverIndicia) {
        assembledByPage[1] = _buildSynthesizedPage(
          blueprint: blueprint,
          pageNumber: 1,
          side: 'right',
          source: BlueprintSlotSource.coverIndicia,
          rule: rule,
          wasFallback: false,
          recipient: recipient,
          headline: blueprint.title.toUpperCase(),
          subhead:
              'VOL. ${blueprint.volume.isEmpty ? "1" : blueprint.volume} · NO. ${blueprint.issue.isEmpty ? "1" : blueprint.issue} · 24-PAGE PERSONALIZED EDITION',
          body:
              'Assembled for **${recipient?.displayName ?? "Editorial Baseline (All Readers)"}** (${recipient?.locationLabel ?? "National Distribution"}).\n\n'
              'Each 24-page issue is dynamically packed from Maker UGC folios, carrier-route correspondence, and weekly programmatic game turns.',
          score: 100.0,
        );
        pageNum++;
        continue;
      }

      if (pageNum == 2 && effectiveSource == BlueprintSlotSource.coverIndicia) {
        assembledByPage[2] = _buildSynthesizedPage(
          blueprint: blueprint,
          pageNumber: 2,
          side: 'left',
          source: BlueprintSlotSource.coverIndicia,
          rule: rule,
          wasFallback: false,
          recipient: recipient,
          headline: 'INDICIA & PERSONALIZATION MANIFEST',
          subhead: 'WEEK ${blueprint.weekId.toUpperCase()} · SHORTCODE /${blueprint.shortCode}',
          body: _buildManifestSummaryText(rules, recipient),
          score: 100.0,
        );
        pageNum++;
        continue;
      }

      // Rank eligible candidates for this slot source
      final candidates = pool
          .where(
            (c) =>
                c.sourceType == effectiveSource && !usedItemIds.contains(c.id),
          )
          .toList();
      candidates.sort(
        (a, b) =>
            scoreCandidate(b, recipient).compareTo(scoreCandidate(a, recipient)),
      );

      if (candidates.isNotEmpty) {
        final top = candidates.first;
        final double topScore = scoreCandidate(top, recipient);

        // Check if the top candidate is a 2-page spread requiring an even ('left') start page
        if (top.pageSpan == 2 &&
            top.sidePreference == 'left' &&
            side == 'right' &&
            pageNum + 2 <= rule.endPage) {
          // Leave current odd (`right`) page as a 1-page pagination gap and backfill with an Ad/Filler!
          final gapAd = _pickBestSinglePageBackfill(
            pool: pool,
            usedItemIds: usedItemIds,
            recipient: recipient,
          );
          if (gapAd != null) usedItemIds.add(gapAd.id);

          assembledByPage[pageNum] = _buildSynthesizedPage(
            blueprint: blueprint,
            pageNumber: pageNum,
            side: 'right',
            source: BlueprintSlotSource.sponsorAd,
            rule: rule,
            wasFallback: false,
            recipient: recipient,
            headline: gapAd?.title ?? 'SPONSOR AD (PAGINATION GAP BACKFILL)',
            subhead:
                'AUTO-INSERTED 1P AD · ALIGNS NEXT 2-PAGE SPREAD TO PAGES ${pageNum + 1}–${pageNum + 2}',
            body: gapAd?.bodyMarkdown ??
                'Placed automatically on Page $pageNum (Right) so the 2-page Maker spread **"${top.title}"** opens flat across Facing Pages ${pageNum + 1} (Left) and ${pageNum + 2} (Right).',
            score: gapAd != null ? scoreCandidate(gapAd, recipient) : 50.0,
            imageUrl: gapAd?.imageUrl,
            gridUrl: gapAd?.gridUrl,
            listUrl: gapAd?.listUrl,
          );

          // Now place the 2-page spread on (pageNum + 1) and (pageNum + 2)
          usedItemIds.add(top.id);
          assembledByPage[pageNum + 1] = _buildSynthesizedPage(
            blueprint: blueprint,
            pageNumber: pageNum + 1,
            side: 'left',
            source: effectiveSource,
            rule: rule,
            wasFallback: wasFallback,
            recipient: recipient,
            headline: '${top.title} (SPREAD LEFT · 1/2)',
            subhead: 'BY ${top.creatorName.toUpperCase()} · 2-PAGE MAKER SPREAD',
            body: top.bodyMarkdown,
            score: topScore,
            hashtags: top.hashtags,
            imageUrl: top.imageUrl,
            gridUrl: top.gridUrl,
            listUrl: top.listUrl,
          );
          assembledByPage[pageNum + 2] = _buildSynthesizedPage(
            blueprint: blueprint,
            pageNumber: pageNum + 2,
            side: 'right',
            source: effectiveSource,
            rule: rule,
            wasFallback: wasFallback,
            recipient: recipient,
            headline: '${top.title} (SPREAD RIGHT · 2/2)',
            subhead: 'BY ${top.creatorName.toUpperCase()} · 2-PAGE MAKER SPREAD',
            body:
                ' Facing spread continuation for **"${top.title}"** (Pages ${pageNum + 1}–${pageNum + 2}).\n\n${top.bodyMarkdown}',
            score: topScore,
            hashtags: top.hashtags,
            imageUrl: top.imageUrl,
            gridUrl: top.gridUrl,
            listUrl: top.listUrl,
          );
          pageNum += 3;
          continue;
        }

        // Normal 2-page spread when already on an even ('left') page
        if (top.pageSpan == 2 &&
            side == 'left' &&
            pageNum + 1 <= rule.endPage &&
            !assembledByPage.containsKey(pageNum + 1)) {
          usedItemIds.add(top.id);
          assembledByPage[pageNum] = _buildSynthesizedPage(
            blueprint: blueprint,
            pageNumber: pageNum,
            side: 'left',
            source: effectiveSource,
            rule: rule,
            wasFallback: wasFallback,
            recipient: recipient,
            headline: '${top.title} (SPREAD LEFT · 1/2)',
            subhead: 'BY ${top.creatorName.toUpperCase()} · 2-PAGE MAKER SPREAD',
            body: top.bodyMarkdown,
            score: topScore,
            hashtags: top.hashtags,
            imageUrl: top.imageUrl,
            gridUrl: top.gridUrl,
            listUrl: top.listUrl,
          );
          assembledByPage[pageNum + 1] = _buildSynthesizedPage(
            blueprint: blueprint,
            pageNumber: pageNum + 1,
            side: 'right',
            source: effectiveSource,
            rule: rule,
            wasFallback: wasFallback,
            recipient: recipient,
            headline: '${top.title} (SPREAD RIGHT · 2/2)',
            subhead: 'BY ${top.creatorName.toUpperCase()} · 2-PAGE MAKER SPREAD',
            body:
                'Facing spread continuation for **"${top.title}"** (Pages $pageNum–${pageNum + 1}).\n\n${top.bodyMarkdown}',
            score: topScore,
            hashtags: top.hashtags,
            imageUrl: top.imageUrl,
            gridUrl: top.gridUrl,
            listUrl: top.listUrl,
          );
          pageNum += 2;
          continue;
        }

        // Single-page placement
        usedItemIds.add(top.id);
        assembledByPage[pageNum] = _buildSynthesizedPage(
          blueprint: blueprint,
          pageNumber: pageNum,
          side: side,
          source: effectiveSource,
          rule: rule,
          wasFallback: wasFallback,
          recipient: recipient,
          headline: top.title,
          subhead: 'BY ${top.creatorName.toUpperCase()}',
          body: top.bodyMarkdown,
          score: topScore,
          hashtags: top.hashtags,
          imageUrl: top.imageUrl,
          gridUrl: top.gridUrl,
          listUrl: top.listUrl,
        );
        pageNum++;
        continue;
      }

      // Fallback synthesized slot when candidate pool is exhausted
      assembledByPage[pageNum] = _buildSynthesizedPage(
        blueprint: blueprint,
        pageNumber: pageNum,
        side: side,
        source: effectiveSource,
        rule: rule,
        wasFallback: wasFallback,
        recipient: recipient,
        headline: '${effectiveSource.label.toUpperCase()} · SLOT #$pageNum',
        subhead: rule.rangeLabel.toUpperCase(),
        body:
            'Template slot reserved for **${effectiveSource.label}** (${rule.rangeLabel}).',
        score: 10.0,
      );
      pageNum++;
    }

    final List<FanzinePage> ordered = [];
    for (int p = 1; p <= 24; p++) {
      ordered.add(assembledByPage[p]!);
    }
    return ordered;
  }

  static BlueprintCandidateItem? _pickBestSinglePageBackfill({
    required List<BlueprintCandidateItem> pool,
    required Set<String> usedItemIds,
    required RecipientFeedContext? recipient,
  }) {
    final ads = pool
        .where(
          (c) =>
              (c.sourceType == BlueprintSlotSource.sponsorAd ||
                  c.sourceType == BlueprintSlotSource.fillerArt) &&
              c.pageSpan == 1 &&
              !usedItemIds.contains(c.id),
        )
        .toList();
    if (ads.isEmpty) return null;
    ads.sort(
      (a, b) =>
          scoreCandidate(b, recipient).compareTo(scoreCandidate(a, recipient)),
    );
    return ads.first;
  }

  static String _buildManifestSummaryText(
    List<BlueprintSlotRule> rules,
    RecipientFeedContext? recipient,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('### ACTIVE RECIPIENT PROFILE');
    if (recipient == null) {
      buffer.writeln(
        '* **Mode:** Editorial Baseline (Select a user in the Publisher panel to simulate personalized feed assembly)',
      );
      buffer.writeln('* **Combat Terminal Player:** Inactive (Pages 7–10 fall back to Global UGC)');
    } else {
      buffer.writeln(
        '* **Recipient:** ${recipient.displayName}${recipient.username != null ? " (@${recipient.username})" : ""}',
      );
      buffer.writeln('* **Carrier Route / Geo:** ${recipient.locationLabel}');
      buffer.writeln(
        '* **Combat Terminal Status:** ${recipient.playsTerminalGame ? "ACTIVE PLAYER (Renders 3-frames/week turn output)" : "INACTIVE (Falls back to Global UGC)"}',
      );
      if (recipient.likedHashtags.isNotEmpty) {
        buffer.writeln(
          '* **Tracked Tag Affinities:** ${recipient.likedHashtags.map((t) => "#$t").join(", ")}',
        );
      }
    }
    buffer.writeln('\n### 24-PAGE BLUEPRINT SLOT RULES');
    for (final r in rules) {
      final resolved = resolveSlotSource(rule: r, recipient: recipient);
      final note = resolved != r.primarySource
          ? ' *(Fallback -> ${resolved.label})*'
          : '';
      buffer.writeln('* **${r.rangeLabel}:** ${r.primarySource.label}$note');
    }
    return buffer.toString();
  }

  static FanzinePage _buildSynthesizedPage({
    required ScheduledFanzine blueprint,
    required int pageNumber,
    required String side,
    required BlueprintSlotSource source,
    required BlueprintSlotRule rule,
    required bool wasFallback,
    required RecipientFeedContext? recipient,
    required String headline,
    required String subhead,
    required String body,
    required double score,
    List<String> hashtags = const [],
    String? imageUrl,
    String? gridUrl,
    String? listUrl,
  }) {
    final String badgeLine = wasFallback
        ? '${source.label} (Fallback from ${rule.primarySource.label})'
        : source.label;
    final String tagsLine = hashtags.isNotEmpty
        ? '\n\n**Tags:** ${hashtags.map((t) => "#$t").join("  ")}'
        : '';

    final String markdown =
        '# $headline\n'
        '### $subhead\n'
        '* **Slot Rule:** ${rule.rangeLabel} — $badgeLine\n'
        '* **Page Alignment:** Page $pageNumber (${side.toUpperCase()}) · Feed Score: ${score.toStringAsFixed(1)}\n\n'
        '$body$tagsLine';

    final String html = TextHtmlRenderer.renderToHtml(markdown);
    final String svgDataUri = _buildBlueprintPageSvgDataUri(
      pageNumber: pageNumber,
      side: side,
      source: source,
      wasFallback: wasFallback,
      headline: headline,
      subhead: subhead,
      ruleLabel: rule.rangeLabel,
      recipientName: recipient?.displayName ?? 'Baseline Template',
      score: score,
      hashtags: hashtags,
    );

    final String pageId = '${blueprint.id}_p$pageNumber';
    return FanzinePage(
      id: pageId,
      pageNumber: pageNumber,
      imageId: pageId,
      imageUrl: imageUrl ?? svgDataUri,
      gridUrl: gridUrl ?? svgDataUri,
      listUrl: listUrl ?? svgDataUri,
      status: 'ready',
      templateId: source.id,
      sidePreference: side,
      width: 2000,
      height: 3200,
      is5x8: true,
      text: markdown,
      textHtml: html,
    );
  }

  /// Generates a crisp 5:8 SVG data URI preview card for Columns 1 & 2 in `/publisher`
  /// so every page in the 24-page blueprint displays its slot type, title, alignment, and feed score visually.
  static String _buildBlueprintPageSvgDataUri({
    required int pageNumber,
    required String side,
    required BlueprintSlotSource source,
    required bool wasFallback,
    required String headline,
    required String subhead,
    required String ruleLabel,
    required String recipientName,
    required double score,
    required List<String> hashtags,
  }) {
    final String accentHex =
        publisherCategoryColors[source.categoryKey] ?? '#6750A4';
    final String cleanHeadline = _escapeXml(
      headline.length > 34 ? '${headline.substring(0, 32)}…' : headline,
    );
    final String cleanSubhead = _escapeXml(
      subhead.length > 48 ? '${subhead.substring(0, 46)}…' : subhead,
    );
    final String cleanSource = _escapeXml(source.label.toUpperCase());
    final String cleanRecipient = _escapeXml(recipientName);
    final String cleanRule = _escapeXml(ruleLabel.toUpperCase());
    final String cleanTags = _escapeXml(
      hashtags.take(3).map((t) => '#$t').join('  '),
    );
    final String fallbackBadge = wasFallback ? ' · FALLBACK ACTIVE' : '';

    final String svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 800" width="500" height="800">
  <rect width="500" height="800" fill="#ffffff"/>
  <rect x="6" y="6" width="488" height="788" fill="none" stroke="#1e293b" stroke-width="4"/>
  <rect x="18" y="18" width="464" height="72" rx="6" fill="$accentHex"/>
  <text x="34" y="48" font-family="Arial, sans-serif" font-size="15" font-weight="bold" fill="#ffffff" letter-spacing="1">$cleanSource$fallbackBadge</text>
  <text x="34" y="72" font-family="monospace" font-size="13" fill="#f8fafc">$cleanRule · ${side.toUpperCase()} PAGE</text>
  <text x="466" y="62" text-anchor="end" font-family="Arial, sans-serif" font-size="32" font-weight="900" fill="#ffffff">P$pageNumber</text>

  <!-- 3-Column Newspaper Wireframe Grid -->
  <line x1="170" y1="110" x2="170" y2="690" stroke="#e2e8f0" stroke-width="2"/>
  <line x1="330" y1="110" x2="330" y2="690" stroke="#e2e8f0" stroke-width="2"/>

  <!-- Content Card -->
  <rect x="30" y="125" width="440" height="210" rx="8" fill="#f8fafc" stroke="$accentHex" stroke-width="2"/>
  <text x="50" y="172" font-family="Arial, sans-serif" font-size="21" font-weight="bold" fill="#0f172a">$cleanHeadline</text>
  <text x="50" y="202" font-family="monospace" font-size="13" font-weight="bold" fill="#475569">$cleanSubhead</text>
  <line x1="50" y1="220" x2="450" y2="220" stroke="#cbd5e1" stroke-width="1"/>
  <text x="50" y="250" font-family="Arial, sans-serif" font-size="14" fill="#334155">Recipient: $cleanRecipient</text>
  <text x="50" y="278" font-family="monospace" font-size="13" font-weight="bold" fill="$accentHex">Feed Match Score: ${score.toStringAsFixed(1)}</text>
  <text x="50" y="308" font-family="monospace" font-size="12" fill="#64748b">$cleanTags</text>

  <!-- Simulated Baseline Typography Bars -->
  <rect x="30" y="365" width="125" height="12" rx="3" fill="#cbd5e1"/>
  <rect x="30" y="390" width="125" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="30" y="410" width="115" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="30" y="430" width="125" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="30" y="465" width="125" height="130" rx="4" fill="#f1f5f9" stroke="#cbd5e1" stroke-dasharray="4,4"/>

  <rect x="185" y="365" width="130" height="12" rx="3" fill="#cbd5e1"/>
  <rect x="185" y="390" width="130" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="185" y="410" width="120" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="185" y="430" width="130" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="185" y="450" width="125" height="10" rx="3" fill="#e2e8f0"/>

  <rect x="345" y="365" width="125" height="12" rx="3" fill="#cbd5e1"/>
  <rect x="345" y="390" width="125" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="345" y="410" width="110" height="10" rx="3" fill="#e2e8f0"/>
  <rect x="345" y="430" width="125" height="10" rx="3" fill="#e2e8f0"/>

  <!-- Footer Strip -->
  <rect x="18" y="725" width="464" height="52" rx="6" fill="#f1f5f9"/>
  <text x="34" y="756" font-family="monospace" font-size="13" font-weight="bold" fill="#475569">BQOPD PUBLISHER BLUEPRINT ENGINE</text>
  <text x="466" y="756" text-anchor="end" font-family="monospace" font-size="13" font-weight="bold" fill="$accentHex">PAGE $pageNumber OF 24</text>
</svg>''';

    return 'data:image/svg+xml;utf8,${Uri.encodeComponent(svg)}';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Rich candidate pool representing uploaded Maker folios (1p and 2p spreads),
  /// Combat Terminal turn outputs, carrier-route local letters, and sponsor ads.
  static List<BlueprintCandidateItem> _buildDefaultCandidatePool(
    ScheduledFanzine blueprint,
    RecipientFeedContext? recipient,
  ) {
    final String userCity = recipient?.city.trim().isNotEmpty == true
        ? recipient!.city.trim()
        : 'La Crosse';
    final String userState = recipient?.state.trim().isNotEmpty == true
        ? recipient!.state.trim()
        : 'WI';
    final String playerName = recipient?.displayName ?? 'Commander';

    return [
      // Combat Terminal Turn Pages (4 pages = Pages 7..10 when player is active)
      BlueprintCandidateItem(
        id: 'term_turn_1',
        title: 'COMBAT TERMINAL · TURN FRAME 1/3',
        creatorName: 'Terminal Engine ($playerName)',
        sourceType: BlueprintSlotSource.terminalTurn,
        hashtags: const ['combat-terminal', 'scifi'],
        likeCount: 42,
        bodyMarkdown:
            'Tactical telemetry for **$playerName** (Frame 1 of 3 this week). Fleet vector locked at Sector 7G; shield harmonics at 84%.',
      ),
      BlueprintCandidateItem(
        id: 'term_turn_2',
        title: 'COMBAT TERMINAL · TURN FRAME 2/3',
        creatorName: 'Terminal Engine ($playerName)',
        sourceType: BlueprintSlotSource.terminalTurn,
        hashtags: const ['combat-terminal', 'scifi'],
        likeCount: 39,
        bodyMarkdown:
            'Orbital intercept resolution (Frame 2 of 3). Opposing cruiser sustained hull breach along starboard battery.',
      ),
      BlueprintCandidateItem(
        id: 'term_turn_3',
        title: 'COMBAT TERMINAL · TURN FRAME 3/3',
        creatorName: 'Terminal Engine ($playerName)',
        sourceType: BlueprintSlotSource.terminalTurn,
        hashtags: const ['combat-terminal', 'scifi'],
        likeCount: 51,
        bodyMarkdown:
            'End-of-week command prompt (Frame 3 of 3). Submit next week\'s maneuver orders via `/terminal` before Sunday 23:59.',
      ),
      BlueprintCandidateItem(
        id: 'term_turn_4',
        title: 'SECTOR STANDINGS & COMBAT LOG',
        creatorName: 'Terminal Adjudicator',
        sourceType: BlueprintSlotSource.terminalTurn,
        hashtags: const ['combat-terminal'],
        likeCount: 28,
        bodyMarkdown:
            'Weekly leaderboard and casualty ledger across active fanzine correspondents.',
      ),

      // Global UGC Folios (Includes 1-page and 2-page spread Maker submissions)
      const BlueprintCandidateItem(
        id: 'ugc_spread_linotype',
        title: 'THE GHOST IN THE LINOTYPE MACHINE',
        creatorName: 'Forrest J. Ackerman',
        creatorId: 'creator_fja',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 2,
        sidePreference: 'left', // Requires even-odd facing spread!Triggers Ad backfill if on odd page
        hashtags: ['scifi', 'linotype', 'weird-tales'],
        likeCount: 88,
        commentCount: 19,
        bodyMarkdown:
            'A two-page centerfold Maker folio chronicling late-night mimeograph and linotype experiments from the early science-fiction press.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_pulp_chronicles',
        title: 'NOTES ON PULP ILLUSTRATION & INK',
        creatorName: 'Hannes Bok',
        creatorId: 'creator_bok',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['pulp-art', 'comics', 'weird-tales'],
        likeCount: 74,
        commentCount: 14,
        bodyMarkdown:
            'Single-page Maker essay on scratchboard shading and high-contrast stippling for 5:8 zine plates.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_astronomy_col',
        title: 'OBSERVATIONS OF THE MARTIAN CANALS',
        creatorName: 'Ray Bradbury',
        creatorId: 'creator_rb',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['astronomy', 'scifi', 'correspondence'],
        likeCount: 65,
        commentCount: 11,
        bodyMarkdown:
            'Submitted via `/maker`: Amateur telescope sketches and speculative dispatches from the autumn opposition.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_con_report',
        title: 'WORLDCON DISPATCH & FANZINE ARCHIVE',
        creatorName: 'Julius Schwartz',
        creatorId: 'creator_js',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 2,
        sidePreference: 'left',
        hashtags: ['conventions', 'reviews', 'correspondence'],
        likeCount: 59,
        commentCount: 9,
        bodyMarkdown:
            'Two-page Maker folio spread featuring annotated photographs and convention hall correspondence.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_weird_verse',
        title: 'SONNETS OF THE OUTER VOID',
        creatorName: 'Clark Ashton Smith',
        creatorId: 'creator_cas',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['weird-tales', 'pulp-art'],
        likeCount: 53,
        commentCount: 7,
        bodyMarkdown:
            'Illustrated verse plate set on the 3-column 42px baseline grid.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_zine_reviews',
        title: 'FANZINE REVIEW ROUNDUP: AUTUMN RELEASES',
        creatorName: 'Sam Moskowitz',
        creatorId: 'creator_sm',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['reviews', 'linotype'],
        likeCount: 47,
        commentCount: 8,
        bodyMarkdown:
            'Critical capsules covering 14 independent folios published by community makers this month.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_comic_strip',
        title: 'STAR-DRIFTER: EPISODE IV',
        creatorName: 'Wally Wood',
        creatorId: 'creator_ww',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['comics', 'scifi', 'pulp-art'],
        likeCount: 92,
        commentCount: 23,
        bodyMarkdown:
            'Serialized 1-page comic strip uploaded through the Profile Maker.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_letter_essay',
        title: 'ON POSTAL APAs & CARRIER ROUTES',
        creatorName: 'Damon Knight',
        creatorId: 'creator_dk',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['correspondence', 'reviews'],
        likeCount: 41,
        commentCount: 6,
        bodyMarkdown:
            'Why physical 24-page saddle-stitched bundles create tighter reader communities than infinite digital feeds.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_type_specimen',
        title: 'ANTON & ARIMO BASELINE SPECIMEN',
        creatorName: 'Typographic Guild',
        creatorId: 'creator_tg',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['linotype', 'pulp-art'],
        likeCount: 36,
        commentCount: 4,
        bodyMarkdown:
            'Reference sheet demonstrating 2000×3200 multi-column baseline grid alignment.',
      ),
      const BlueprintCandidateItem(
        id: 'ugc_retro_hardware',
        title: 'TELETYPE TERMINALS & ACOUSTIC COUPLERS',
        creatorName: 'Lee Felsenstein',
        creatorId: 'creator_lf',
        sourceType: BlueprintSlotSource.globalUgc,
        pageSpan: 1,
        hashtags: ['combat-terminal', 'linotype', 'scifi'],
        likeCount: 49,
        commentCount: 10,
        bodyMarkdown:
            'Connecting paper-tape terminals to weekly print-run games.',
      ),

      // Local / Carrier-Route UGC & Radius Letters
      BlueprintCandidateItem(
        id: 'local_letter_1',
        title: 'CARRIER ROUTE DISPATCH: ${userCity.toUpperCase()}, $userState',
        creatorName: 'Local Correspondent ($userCity)',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['correspondence', 'conventions'],
        likeCount: 64,
        commentCount: 12,
        bodyMarkdown:
            'Local UGC & Radius Letter matched to **$userCity, $userState** carrier route.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_2',
        title: 'REGIONAL MEETUP & PRINT EXCHANGE ($userCity)',
        creatorName: '$userCity Zine Collective',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['conventions', 'linotype'],
        likeCount: 52,
        commentCount: 9,
        bodyMarkdown:
            'Monthly portfolio swap and letterpress workshop notices within 25 miles of **$userCity, $userState**.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_3',
        title: 'ARCHIVE LETTER FROM THE $userState HISTORICAL POOL',
        creatorName: 'Regional Archivist',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['correspondence', 'weird-tales'],
        likeCount: 44,
        commentCount: 5,
        bodyMarkdown:
            'Geohash-matched archival correspondence from readers near **$userCity, $userState**.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_4',
        title: 'LOCAL MAKER SPOTLIGHT: $userCity',
        creatorName: 'Neighborhood Press',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['pulp-art', 'comics'],
        likeCount: 38,
        commentCount: 4,
        bodyMarkdown:
            'Recent single-page illustrations uploaded by creators in your postal sector.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_5',
        title: 'POSTAL EXCHANGE DIRECTORY ($userState)',
        creatorName: 'Circulation Desk',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['correspondence'],
        likeCount: 31,
        commentCount: 3,
        bodyMarkdown:
            'Active correspondents and trading posts in the **$userCity, $userState** radius.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_6',
        title: 'LETTERS TO THE EDITOR · LOCAL DESK',
        creatorName: 'Readers in $userState',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['correspondence', 'reviews'],
        likeCount: 29,
        commentCount: 6,
        bodyMarkdown:
            'Replies and margin commentary on last week\'s 72-page bundle from nearby subscribers.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_7',
        title: 'CARRIER ROUTE BULLETIN & CLASSIFIEDS',
        creatorName: '$userCity Swap Board',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['linotype', 'conventions'],
        likeCount: 25,
        commentCount: 2,
        bodyMarkdown:
            'Typewriters, mimeograph stencils, and vintage zine duplicates available locally.',
      ),
      BlueprintCandidateItem(
        id: 'local_letter_8',
        title: 'CLOSING REGIONAL CORRESPONDENCE',
        creatorName: '$userCity Bureau',
        sourceType: BlueprintSlotSource.localUgc,
        city: userCity,
        state: userState,
        hashtags: const ['correspondence'],
        likeCount: 22,
        commentCount: 2,
        bodyMarkdown:
            'Final local dispatch for this week\'s 24-page imprint.',
      ),

      // Sponsor Ads & 1-Page Backfills
      const BlueprintCandidateItem(
        id: 'ad_back_cover',
        title: 'ACME MIMEOGRAPH & INK SUPPLY CO.',
        creatorName: 'Sponsor Plate #101',
        sourceType: BlueprintSlotSource.sponsorAd,
        pageSpan: 1,
        hashtags: ['linotype', 'pulp-art'],
        likeCount: 30,
        bodyMarkdown:
            'Full-page vintage sponsor plate. Used for Back Cover (Page 24) or automatic 1-page pagination gap backfill.',
      ),
      const BlueprintCandidateItem(
        id: 'ad_cosmic_books',
        title: 'COSMIC BOOKSHOP · RARE PULPS & ZINES',
        creatorName: 'Sponsor Plate #102',
        sourceType: BlueprintSlotSource.sponsorAd,
        pageSpan: 1,
        hashtags: ['weird-tales', 'scifi', 'reviews'],
        likeCount: 27,
        bodyMarkdown:
            'Single-page advertisement automatically selected to pad odd/even spread alignments.',
      ),
      const BlueprintCandidateItem(
        id: 'ad_terminal_recruit',
        title: 'ENLIST IN THE COMBAT TERMINAL (3 FRAMES / WEEK)',
        creatorName: 'System House Ad',
        sourceType: BlueprintSlotSource.sponsorAd,
        pageSpan: 1,
        hashtags: ['combat-terminal', 'scifi'],
        likeCount: 35,
        bodyMarkdown:
            'House recruitment ad inviting readers to join the weekly turn-based Combat Terminal game.',
      ),

      // Filler & Spot Art
      const BlueprintCandidateItem(
        id: 'filler_spot_1',
        title: 'WOODCUT ASTRONOMY PLATE',
        creatorName: 'Archive Spot Art',
        sourceType: BlueprintSlotSource.fillerArt,
        pageSpan: 1,
        hashtags: ['astronomy', 'pulp-art'],
        likeCount: 33,
        bodyMarkdown:
            'Full-page archival woodcut illustration used for signature balance.',
      ),
      const BlueprintCandidateItem(
        id: 'filler_spot_2',
        title: 'LINOTYPE ORNAMENT & COLOPHON SPECIMEN',
        creatorName: 'Archive Spot Art',
        sourceType: BlueprintSlotSource.fillerArt,
        pageSpan: 1,
        hashtags: ['linotype'],
        likeCount: 24,
        bodyMarkdown:
            'Decorative printer ornaments and borders.',
      ),
    ];
  }
}
