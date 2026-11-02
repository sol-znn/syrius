part of 'send_populated.dart';

class _SendContactsPicker extends StatefulWidget {
  const _SendContactsPicker({required this.contacts, required this.sender});

  final ContactsStore contacts;
  final SendTransactionBloc sender;

  @override
  State<_SendContactsPicker> createState() => _SendContactsPickerState();
}

class _SendContactsPickerState extends State<_SendContactsPicker> {
  final TextEditingController _search = TextEditingController();
  bool _decided = false;

  void _finish(String? address) {
    // A second retained callback can run before the route leaves the tree.
    // Only the first decision belongs to this picker.
    if (_decided || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _decided = true;
    Navigator.of(context).pop(address);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return DialogCard(
      title: context.l10n.sendAddressBook,
      width: tokens.goToWidth,
      actions: <Widget>[
        TextButton(
          onPressed: () => _finish(null),
          child: Text(context.l10n.commonClose),
        ),
      ],
      body: SizedBox(
        width: tokens.goToWidth,
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            _search,
            widget.contacts,
            widget.sender.busy,
          ]),
          builder: (_, _) {
            final List<Contact> contacts = widget.contacts.search(_search.text);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: const Key('send_contacts_search'),
                  controller: _search,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.l10n.sendSearchContacts,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                SizedBox(height: tokens.transferFormGap),
                if (widget.contacts.readFailed)
                  Text(
                    context.l10n.sendContactsUnavailable,
                    key: const Key('send_contacts_read_failed'),
                    style: tokens.transferCaptionText,
                  )
                else if (contacts.isEmpty)
                  Text(
                    context.l10n.nodesNoneYet,
                    key: const Key('send_contacts_empty'),
                    style: tokens.transferCaptionText,
                  ),
                if (contacts.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    // The frosted card paints an opaque surface above its
                    // outer Material. Keep each tile's ink on that surface.
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        itemBuilder: (_, int index) {
                          final Contact contact = contacts[index];
                          return ListTile(
                            key: ValueKey<String>(
                              'send_contact_${contact.address}',
                            ),
                            enabled: !widget.sender.busy.value,
                            title: Text(contact.name, style: tokens.bodyText),
                            subtitle: Tooltip(
                              message: contact.address,
                              child: Text(
                                contact.address,
                                textDirection: TextDirection.ltr,
                                textAlign: ltrTextAlign(context),
                                style: tokens.dataText.copyWith(
                                  color: tokens.dim,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () {
                              // Retained callbacks recheck the live sender.
                              if (widget.sender.busy.value ||
                                  ContactsStore.normalize(contact.address) !=
                                      contact.address ||
                                  widget.contacts.byAddress(contact.address) !=
                                      contact) {
                                return;
                              }
                              _finish(contact.address);
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
