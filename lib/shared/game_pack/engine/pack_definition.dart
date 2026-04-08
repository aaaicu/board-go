/// JSON-serializable definition of a game pack's rules.
///
/// This is the "data" part of the rules engine: it describes all phases,
/// actions, conditions, effects, and view-building logic for a game pack
/// in a declarative JSON DSL format.
///
/// The [JsonDrivenRules] engine interprets this definition at runtime.
class PackDefinition {
  final String packId;
  final int minPlayers;
  final int maxPlayers;
  final String boardOrientation;
  final String nodeOrientation;

  /// DSL expression/effects for creating the initial game state.
  /// Must produce a Map that becomes `gameState.data`.
  final Map<String, dynamic> setup;

  /// Map of phase name → phase definition.
  final Map<String, PhaseDefinition> phases;

  /// Rules for building the board view (public state).
  final Map<String, dynamic> boardView;

  /// Rules for building the player view (private state per player).
  final Map<String, dynamic> playerView;

  /// Rules for checking game end conditions.
  final Map<String, dynamic> gameEnd;

  /// Optional node message filtering rules.
  final Map<String, dynamic>? nodeMessages;

  const PackDefinition({
    required this.packId,
    required this.minPlayers,
    required this.maxPlayers,
    this.boardOrientation = 'landscape',
    this.nodeOrientation = 'portrait',
    required this.setup,
    required this.phases,
    required this.boardView,
    required this.playerView,
    required this.gameEnd,
    this.nodeMessages,
  });

  factory PackDefinition.fromJson(Map<String, dynamic> json) {
    final phasesJson = json['phases'] as Map<String, dynamic>;
    final phases = phasesJson.map(
      (k, v) => MapEntry(k, PhaseDefinition.fromJson(v as Map<String, dynamic>)),
    );

    return PackDefinition(
      packId: json['packId'] as String,
      minPlayers: json['minPlayers'] as int,
      maxPlayers: json['maxPlayers'] as int,
      boardOrientation: json['boardOrientation'] as String? ?? 'landscape',
      nodeOrientation: json['nodeOrientation'] as String? ?? 'portrait',
      setup: json['setup'] as Map<String, dynamic>,
      phases: phases,
      boardView: json['boardView'] as Map<String, dynamic>,
      playerView: json['playerView'] as Map<String, dynamic>,
      gameEnd: json['gameEnd'] as Map<String, dynamic>,
      nodeMessages: json['nodeMessages'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'packId': packId,
        'minPlayers': minPlayers,
        'maxPlayers': maxPlayers,
        'boardOrientation': boardOrientation,
        'nodeOrientation': nodeOrientation,
        'setup': setup,
        'phases': phases.map((k, v) => MapEntry(k, v.toJson())),
        'boardView': boardView,
        'playerView': playerView,
        'gameEnd': gameEnd,
        if (nodeMessages != null) 'nodeMessages': nodeMessages,
      };
}

/// Definition of a single game phase.
class PhaseDefinition {
  /// Map of action type → action definition.
  final Map<String, ActionDefinition> actions;

  /// Optional effects to run when entering this phase.
  final List<dynamic>? onEnter;

  /// If true (default), only the active player can take actions in this phase.
  /// Set to false for phases where all players act (e.g. voting).
  final bool activePlayerOnly;

  const PhaseDefinition({
    required this.actions,
    this.onEnter,
    this.activePlayerOnly = true,
  });

  factory PhaseDefinition.fromJson(Map<String, dynamic> json) {
    final actionsJson = json['actions'] as Map<String, dynamic>? ?? {};
    final actions = actionsJson.map(
      (k, v) =>
          MapEntry(k, ActionDefinition.fromJson(v as Map<String, dynamic>)),
    );
    return PhaseDefinition(
      actions: actions,
      onEnter: json['onEnter'] as List?,
      activePlayerOnly: json['activePlayerOnly'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'actions': actions.map((k, v) => MapEntry(k, v.toJson())),
        if (onEnter != null) 'onEnter': onEnter,
        if (!activePlayerOnly) 'activePlayerOnly': activePlayerOnly,
      };
}

/// Definition of a single action within a phase.
class ActionDefinition {
  /// DSL expression that determines which players can take this action.
  /// Evaluated per-player. If null/true, any alive player can act.
  final dynamic allowedWhen;

  /// DSL expression that generates the list of allowed action instances.
  /// Each entry should produce {actionType, label, params}.
  /// If null, a single action with no params is generated when allowedWhen is true.
  final dynamic generate;

  /// Label template for the action button.
  final dynamic label;

  /// Parameter definitions for this action.
  final Map<String, dynamic>? params;

  /// Effects to execute when this action is taken.
  final List<dynamic> effects;

  const ActionDefinition({
    this.allowedWhen,
    this.generate,
    this.label,
    this.params,
    required this.effects,
  });

  factory ActionDefinition.fromJson(Map<String, dynamic> json) {
    return ActionDefinition(
      allowedWhen: json['allowedWhen'],
      generate: json['generate'],
      label: json['label'],
      params: json['params'] as Map<String, dynamic>?,
      effects: json['effects'] as List? ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        if (allowedWhen != null) 'allowedWhen': allowedWhen,
        if (generate != null) 'generate': generate,
        if (label != null) 'label': label,
        if (params != null) 'params': params,
        'effects': effects,
      };
}
