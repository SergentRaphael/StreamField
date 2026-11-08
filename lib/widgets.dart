import 'package:flutter/material.dart';

import 'models/channel.dart';
import 'theme.dart';

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/branding/icon.png', width: 28, height: 28),
        const SizedBox(width: 8),
        const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Stream'),
            TextSpan(text: 'Field', style: TextStyle(color: kAccent)),
          ]),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
      ],
    );
  }
}

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.live_tv_rounded, size: size * 0.5, color: kMuted);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: url == null
          ? fallback
          : Image.network(
              url!,
              fit: BoxFit.contain,
              cacheWidth: (size * 2.5).round(), // économise la mémoire
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status});

  final StreamStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      StreamStatus.unknown => const SizedBox(width: 12),
      StreamStatus.checking => const SizedBox(
          width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
      StreamStatus.ok => const Tooltip(
          message: 'En ligne', child: Icon(Icons.circle, size: 10, color: kAccent)),
      StreamStatus.dead => const Tooltip(
          message: 'Hors ligne', child: Icon(Icons.circle, size: 10, color: kDanger)),
    };
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    this.autofocus = false,
  });

  final Channel channel;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      autofocus: autofocus,
      leading: ChannelLogo(url: channel.logo),
      title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        channel.group,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: kMuted, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(status: channel.status),
          IconButton(
            tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: favorite ? kAccent : kMuted,
            ),
            onPressed: onFavorite,
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onFavorite,
    );
  }
}

// ---------- Petite boîte de dialogue à champs ----------

class FieldSpec {
  const FieldSpec(this.label, {this.hint, this.obscure = false, this.initial = ''});

  final String label;
  final String? hint;
  final bool obscure;
  final String initial;
}

Future<List<String>?> askFields(
  BuildContext context,
  String title,
  List<FieldSpec> fields,
) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _FieldsDialog(title: title, fields: fields),
  );
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({required this.title, required this.fields});

  final String title;
  final List<FieldSpec> fields;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final List<TextEditingController> _ctrls = [
    for (final f in widget.fields) TextEditingController(text: f.initial),
  ];

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() => Navigator.pop(context, [for (final c in _ctrls) c.text]);

  @override
  Widget build(BuildContext context) {
    final last = widget.fields.length - 1;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _ctrls[i],
                    autofocus: i == 0,
                    obscureText: widget.fields[i].obscure,
                    autocorrect: false,
                    textInputAction: i == last ? TextInputAction.done : TextInputAction.next,
                    onSubmitted: i == last ? (_) => _ok() : null,
                    decoration: InputDecoration(
                      labelText: widget.fields[i].label,
                      hintText: widget.fields[i].hint,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _ok, child: const Text('Valider')),
      ],
    );
  }
}
