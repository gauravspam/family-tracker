/// Catalog of preset avatars. IDs are stored in Traccar device attributes
/// under key "avatarId". Assets are OpenMoji SVGs (CC BY-SA 4.0).
class AvatarCatalog {
  static const List<AvatarPreset> all = [
    AvatarPreset(id: 'avatar_father',      label: 'Father',      asset: 'assets/avatars/avatar_father.svg'),
    AvatarPreset(id: 'avatar_mother',      label: 'Mother',      asset: 'assets/avatars/avatar_mother.svg'),
    AvatarPreset(id: 'avatar_brother',     label: 'Brother',     asset: 'assets/avatars/avatar_brother.svg'),
    AvatarPreset(id: 'avatar_sister',      label: 'Sister',      asset: 'assets/avatars/avatar_sister.svg'),
    AvatarPreset(id: 'avatar_grandfather', label: 'Grandfather', asset: 'assets/avatars/avatar_grandfather.svg'),
    AvatarPreset(id: 'avatar_grandmother', label: 'Grandmother', asset: 'assets/avatars/avatar_grandmother.svg'),
    AvatarPreset(id: 'avatar_boy',         label: 'Boy',         asset: 'assets/avatars/avatar_boy.svg'),
    AvatarPreset(id: 'avatar_girl',        label: 'Girl',        asset: 'assets/avatars/avatar_girl.svg'),
    AvatarPreset(id: 'avatar_friend_m',    label: 'Friend (M)',  asset: 'assets/avatars/avatar_friend_m.svg'),
    AvatarPreset(id: 'avatar_friend_f',    label: 'Friend (F)',  asset: 'assets/avatars/avatar_friend_f.svg'),
    AvatarPreset(id: 'avatar_default',     label: 'Person',      asset: 'assets/avatars/avatar_default.svg'),
  ];

  static AvatarPreset find(String? id) {
    if (id == null) return _default;
    return all.firstWhere((a) => a.id == id, orElse: () => _default);
  }

  static AvatarPreset get _default =>
      all.firstWhere((a) => a.id == 'avatar_default');
}

class AvatarPreset {
  final String id;
  final String label;
  final String asset;

  const AvatarPreset({
    required this.id,
    required this.label,
    required this.asset,
  });
}
