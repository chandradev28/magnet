import 'package:flutter/material.dart';

import '../theme.dart';

Widget kickerText(String text) => Text(
      text,
      style: const TextStyle(
        color: lime,
        fontSize: 12,
        letterSpacing: 2.2,
        fontWeight: FontWeight.w900,
      ),
    );

Widget screenHeading({
  required String kicker,
  required String title,
  required String subtitle,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      kickerText(kicker),
      const SizedBox(height: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 33,
          height: 1.05,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.3,
        ),
      ),
      const SizedBox(height: 10),
      Text(subtitle, style: const TextStyle(color: muted, height: 1.45)),
    ],
  );
}

Widget statTile(String label, String value, IconData icon) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: muted, size: 16),
      const SizedBox(height: 6),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

Widget infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

Widget pillChip(IconData icon, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: panelRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: chipBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: lime),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

Widget busyCard(String label) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget progressBar(double? value) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 7,
      backgroundColor: track,
      color: lime,
    ),
  );
}

Widget emptyCard({
  required IconData icon,
  required String title,
  required String body,
}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, color: lime, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}
