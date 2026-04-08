import '../pack_definition.dart';

/// Returns the JSON DSL pack definition for SimpleCardGame.
///
/// This replaces the compiled [SimpleCardGameRules] with a data-driven
/// definition interpreted by [JsonDrivenRules].
PackDefinition simpleCardGameDefinition() {
  return PackDefinition.fromJson(_kDefinition);
}

const Map<String, dynamic> _kDefinition = {
  'packId': 'simple_card_game',
  'minPlayers': 2,
  'maxPlayers': 4,
  'boardOrientation': 'landscape',
  'nodeOrientation': 'portrait',

  // ---------------------------------------------------------------------------
  // Setup: create initial game state
  // ---------------------------------------------------------------------------
  'setup': {
    'initialData': {
      'phase': 'main',
      'hands': {'literal': {}},
      'deck': {'literal': []},
      'discardPile': {'literal': []},
      'scores': {'literal': {}},
    },
    'effects': [
      // Build deck: for each suit × rank
      {
        'let': {
          r'$suits': {'literal': ['clubs', 'diamonds', 'hearts', 'spades']},
          r'$ranks': {
            'literal': [
              'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'
            ]
          },
        },
        'do': [
          {
            'set': {
              'flatten': {
                'map': {
                  'list': {'var': r'$suits'},
                  'as': r'$suit',
                  'to': {
                    'map': {
                      'list': {'var': r'$ranks'},
                      'as': r'$rank',
                      'to': {'cat': [{'var': r'$rank'}, '-', {'var': r'$suit'}]},
                    }
                  },
                }
              }
            },
            'path': 'deck',
          },
        ],
      },
      // Shuffle deck
      {'shuffleDeck': 'deck'},
      // Initialize scores for each player
      {
        'forEach': {'var': 'playerOrder'},
        'as': r'$pid',
        'do': [
          {'set': 0, 'path': r'scores.{$pid}'},
        ],
      },
      // Deal 5 cards to each player
      {
        'forEach': {'var': 'playerOrder'},
        'as': r'$pid',
        'do': [
          {'set': {'literal': []}, 'path': r'hands.{$pid}'},
          {
            'drawCards': {
              'from': 'deck',
              'to': r'hands.{$pid}',
              'count': 5,
            },
          },
        ],
      },
    ],
    'log': [
      {
        'eventType': 'system',
        'description': 'Game started',
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // Phases
  // ---------------------------------------------------------------------------
  'phases': {
    'main': {
      'actions': {
        // PLAY_CARD: one per card in hand
        'PLAY_CARD': {
          'generate': {
            'forEach': {'var': 'hands.{playerId}'},
            'as': r'$card',
            'label': {'cat': ['Play ', {'var': r'$card'}]},
            'params': {
              'cardId': {'var': r'$card'},
            },
          },
          'effects': [
            // Remove card from hand
            {'remove': 'hands.{playerId}', 'value': {'var': 'action.cardId'}},
            // Add to discard pile
            {'append': 'discardPile', 'value': {'var': 'action.cardId'}},
            // Increment score
            {'increment': 'scores.{playerId}', 'by': 1},
            // Log
            {
              'log': 'PLAY_CARD',
              'message': {
                'cat': [{'var': 'playerId'}, ' played ', {'var': 'action.cardId'}]
              },
            },
          ],
        },

        // DRAW_CARD: only if deck is not empty
        'DRAW_CARD': {
          'allowedWhen': {
            'isNotEmpty': {'var': 'deck'},
          },
          'label': 'Draw Card',
          'effects': [
            {
              'drawCards': {
                'from': 'deck',
                'to': 'hands.{playerId}',
                'count': 1,
              }
            },
            {
              'log': 'DRAW_CARD',
              'message': {'cat': [{'var': 'playerId'}, ' drew a card']},
            },
          ],
        },

        // END_TURN: always available
        'END_TURN': {
          'label': 'End Turn',
          'effects': [
            {'advanceTurn': true},
            {
              'log': 'END_TURN',
              'message': {'cat': [{'var': 'playerId'}, ' ended turn']},
            },
          ],
        },
      },
    },
  },

  // ---------------------------------------------------------------------------
  // Game end
  // ---------------------------------------------------------------------------
  'gameEnd': {
    'condition': {
      'or': [
        {'isEmpty': {'var': 'deck'}},
        {'>': [{'var': 'round'}, 10]},
      ]
    },
    'winners': {
      'let': {
        r'$maxScore': {
          'reduce': {
            'list': {'values': {'var': 'scores'}},
            'as': r'$s',
            'acc': r'$best',
            'init': 0,
            'to': {'max': [{'var': r'$best'}, {'var': r'$s'}]},
          }
        },
      },
      'in': {
        'filter': {
          'list': {'keys': {'var': 'scores'}},
          'as': r'$pid',
          'where': {
            '==': [
              {'get': [{'var': 'scores'}, {'var': r'$pid'}]},
              {'var': r'$maxScore'},
            ]
          },
        }
      },
    },
  },

  // ---------------------------------------------------------------------------
  // Board view
  // ---------------------------------------------------------------------------
  'boardView': {
    'scores': {'var': 'scores'},
    'deckRemaining': {'length': {'var': 'deck'}},
    'discardPile': {
      'if': [
        {'>': [{'length': {'var': 'discardPile'}}, 5]},
        {'slice': {'list': {'var': 'discardPile'}, 'last': 5}},
        {'var': 'discardPile'},
      ]
    },
    'maxRecentLog': 10,
  },

  // ---------------------------------------------------------------------------
  // Player view
  // ---------------------------------------------------------------------------
  'playerView': {
    'hand': {'var': 'hands.{playerId}'},
    'scores': {'var': 'scores'},
  },

  // ---------------------------------------------------------------------------
  // Node messages
  // ---------------------------------------------------------------------------
  'nodeMessages': {
    'allowedTypes': {'literal': ['emote', 'chat']},
    'validate': {
      'emote': {
        'and': [
          {'!=': [{'var': 'action.payload.emoji'}, null]},
          {
            'in': [
              {'var': 'action.payload.emoji'},
              {'literal': ['👍', '👎', '😂', '😢', '😡', '🎉', '🤔', '😱']},
            ]
          },
        ]
      },
      'chat': {
        'and': [
          {'!=': [{'var': 'action.payload.text'}, null]},
          {'isNotEmpty': {'var': 'action.payload.text'}},
          {'<=': [{'length': {'var': 'action.payload.text'}}, 100]},
        ]
      },
    },
  },
};
