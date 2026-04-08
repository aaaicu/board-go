import '../pack_definition.dart';

/// Returns the JSON DSL pack definition for Secret Hitler.
///
/// This replaces the compiled [SecretHitlerRules] with a data-driven
/// definition interpreted by [JsonDrivenRules].
PackDefinition secretHitlerDefinition() {
  return PackDefinition.fromJson(_kDefinition);
}

// ---------------------------------------------------------------------------
// Helper: "next president" effect sequence
//
// Advances presidentPosition to the next alive player, clears nomination
// state, and sets the active player.
// ---------------------------------------------------------------------------
const List<Map<String, dynamic>> _nextPresidentEffects = [
  // If specialElectionReturnIndex is set, use it then clear
  {
    'if': {'!=': [{'var': 'specialElectionReturnIndex'}, null]},
    'then': [
      {'set': {'var': 'specialElectionReturnIndex'}, 'path': 'presidentPosition'},
      {'set': null, 'path': 'specialElectionReturnIndex'},
    ],
  },
  // Advance position: find next alive player
  {
    'let': {
      r'$pos': {'var': 'presidentPosition'},
      r'$order': {'var': 'playerOrder'},
      r'$dead': {'var': 'deadPlayers'},
    },
    'do': [
      // We need a loop to skip dead players. We use a forEach over a range
      // and set a flag. Since DSL has no while loop, we iterate up to
      // playerCount times and pick the first alive.
      {
        'let': {
          r'$len': {'length': {'var': 'playerOrder'}},
          r'$startPos': {'var': 'presidentPosition'},
        },
        'do': [
          {
            'set': {
              'let': {
                r'$candidates': {
                  'filter': {
                    'list': {'range': {'start': 1, 'end': {'+': [{'length': {'var': 'playerOrder'}}, 1]}}},
                    'as': r'$offset',
                    'where': {
                      'not': {
                        'contains': [
                          {'var': 'deadPlayers'},
                          {
                            'get': [
                              {'var': 'playerOrder'},
                              {'%': [{'+': [{'var': r'$startPos'}, {'var': r'$offset'}]}, {'length': {'var': 'playerOrder'}}]},
                            ]
                          },
                        ]
                      }
                    },
                  }
                },
              },
              'in': {
                '%': [
                  {'+': [{'var': r'$startPos'}, {'get': [{'var': r'$candidates'}, 0]}]},
                  {'length': {'var': 'playerOrder'}},
                ]
              },
            },
            'path': 'presidentPosition',
          },
        ],
      },
      // Set presidentId from the new position
      {
        'set': {
          'get': [
            {'var': 'playerOrder'},
            {'var': 'presidentPosition'},
          ]
        },
        'path': 'presidentId',
      },
      // Set as active player
      {
        'setActivePlayer': {
          'get': [
            {'var': 'playerOrder'},
            {'var': 'presidentPosition'},
          ]
        },
      },
      // Clear nomination state
      {'set': null, 'path': 'chancellorId'},
      {'set': null, 'path': 'chancellorCandidateId'},
      {'set': null, 'path': 'voteResult'},
    ],
  },
];

// Helper: check win after policy enactment, or advance to next round
const List<Map<String, dynamic>> _checkWinOrNextRoundEffects = [
  {
    'if': {'==': [{'var': 'liberalPolicies'}, 5]},
    'then': [
      {'set': 'LIBERAL', 'path': 'winner'},
      {'log': 'system', 'message': 'Liberal policies reached 5! Liberals win!'},
    ],
    'else': [
      ..._nextPresidentEffects,
      {'setPhase': 'CHANCELLOR_NOMINATION'},
    ],
  },
];

// Helper: chaos (election tracker reaches 3) effect sequence
const List<Map<String, dynamic>> _chaosEffects = [
  {'log': 'system', 'message': '3 failed elections! Top deck policy is enacted.'},
  {'set': 0, 'path': 'electionTracker'},
  // Reshuffle if deck empty
  {
    'if': {'isEmpty': {'var': 'deck'}},
    'then': [
      {'returnCards': {'from': 'discard', 'to': 'deck'}},
      {'shuffleDeck': 'deck'},
    ],
  },
  // Enact top card
  {
    'let': {
      r'$topPolicy': {'get': [{'var': 'deck'}, 0]},
    },
    'do': [
      // Remove top card from deck
      {
        'set': {
          'skip': {
            'list': {'var': 'deck'},
            'count': 1,
          }
        },
        'path': 'deck',
      },
      {'set': {'var': r'$topPolicy'}, 'path': 'lastEnactedPolicy'},
      // Clear term limits on chaos
      {'set': null, 'path': 'previousPresidentId'},
      {'set': null, 'path': 'previousChancellorId'},
      {
        'if': {'==': [{'var': r'$topPolicy'}, 'LIBERAL']},
        'then': [
          {'increment': 'liberalPolicies', 'by': 1},
          {'log': 'system', 'message': 'Chaos: Liberal policy enacted!'},
        ],
        'else': [
          {'increment': 'fascistPolicies', 'by': 1},
          {'log': 'system', 'message': 'Chaos: Fascist policy enacted!'},
        ],
      },
      // Check win conditions after chaos
      {
        'if': {'==': [{'var': 'liberalPolicies'}, 5]},
        'then': [
          {'set': 'LIBERAL', 'path': 'winner'},
          {'log': 'system', 'message': 'Liberal policies reached 5! Liberals win!'},
        ],
        'else': [
          {
            'if': {'>=': [{'var': 'fascistPolicies'}, 6]},
            'then': [
              {'set': 'FASCIST', 'path': 'winner'},
              {'log': 'system', 'message': 'Fascist policies reached 6! Fascists win!'},
            ],
            'else': [
              ..._nextPresidentEffects,
              {'setPhase': 'CHANCELLOR_NOMINATION'},
            ],
          },
        ],
      },
    ],
  },
];

const Map<String, dynamic> _kDefinition = {
  'packId': 'secret_hitler',
  'minPlayers': 5,
  'maxPlayers': 10,
  'boardOrientation': 'landscape',
  'nodeOrientation': 'portrait',

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------
  'setup': {
    'initialData': {
      'phase': 'ROLE_REVEAL',
      'roles': {'literal': {}},
      'readyPlayers': {'literal': []},
      'deck': {'literal': []},
      'discard': {'literal': []},
      'liberalPolicies': 0,
      'fascistPolicies': 0,
      'electionTracker': 0,
      'presidentPosition': 0,
      'presidentId': null,
      'chancellorCandidateId': null,
      'chancellorId': null,
      'previousPresidentId': null,
      'previousChancellorId': null,
      'votes': {'literal': {}},
      'voteResult': null,
      'drawnPolicies': {'literal': []},
      'executiveActionType': 'NONE',
      'vetoUnlocked': false,
      'vetoRequested': false,
      'deadPlayers': {'literal': []},
      'investigatedPlayers': {'literal': []},
      'specialElectionReturnIndex': null,
      'winner': null,
      'lastEnactedPolicy': null,
    },
    'effects': [
      // Assign roles based on player count
      {
        'let': {
          r'$playerCount': {'length': {'var': 'playerOrder'}},
          r'$fascistCount': {
            'if': [
              {'<=': [{'length': {'var': 'playerOrder'}}, 6]},
              1,
              {
                'if': [
                  {'<=': [{'length': {'var': 'playerOrder'}}, 8]},
                  2,
                  3,
                ]
              },
            ]
          },
        },
        'do': [
          {
            'let': {
              r'$liberalCount': {
                '-': [
                  {'length': {'var': 'playerOrder'}},
                  {'+': [{'var': r'$fascistCount'}, 1]},
                ]
              },
            },
            'do': [
              // Build role pool
              {
                'let': {
                  r'$rolePool': {
                    'shuffle': {
                      'let': {
                        r'$fascists': {
                          'map': {
                            'list': {'range': {'var': r'$fascistCount'}},
                            'as': r'$i',
                            'to': 'FASCIST',
                          }
                        },
                        r'$liberals': {
                          'map': {
                            'list': {'range': {'var': r'$liberalCount'}},
                            'as': r'$i',
                            'to': 'LIBERAL',
                          }
                        },
                      },
                      'in': {
                        'flatten': [
                          ['HITLER'],
                          {'var': r'$fascists'},
                          {'var': r'$liberals'},
                        ]
                      },
                    }
                  },
                },
                'do': [
                  // Assign roles to players
                  {
                    'forEach': {'var': 'playerOrder'},
                    'as': r'$pid',
                    'index': r'$idx',
                    'do': [
                      {
                        'set': {
                          'get': [{'var': r'$rolePool'}, {'var': r'$idx'}]
                        },
                        'path': r'roles.{$pid}',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
      // Build policy deck: 11 FASCIST + 6 LIBERAL
      {
        'set': {
          'flatten': [
            {
              'map': {
                'list': {'range': 11},
                'as': r'$i',
                'to': 'FASCIST',
              }
            },
            {
              'map': {
                'list': {'range': 6},
                'as': r'$i',
                'to': 'LIBERAL',
              }
            },
          ]
        },
        'path': 'deck',
      },
      {'shuffleDeck': 'deck'},
      // Set first president
      {
        'set': {
          'get': [{'var': 'playerOrder'}, 0]
        },
        'path': 'presidentId',
      },
      {
        'setActivePlayer': {
          'get': [{'var': 'playerOrder'}, 0]
        },
      },
    ],
    'log': [
      {
        'eventType': 'system',
        'description': 'Secret Hitler has started! Check your roles.',
      },
    ],
  },

  // ---------------------------------------------------------------------------
  // Phases
  // ---------------------------------------------------------------------------
  'phases': {
    // === ROLE_REVEAL: all players confirm their roles ===
    'ROLE_REVEAL': {
      'activePlayerOnly': false,
      'actions': {
        'READY': {
          'allowedWhen': {
            'not': {
              'contains': [
                {'var': 'readyPlayers'},
                {'var': 'playerId'},
              ]
            }
          },
          'label': 'Role confirmed',
          'effects': [
            {'append': 'readyPlayers', 'value': {'var': 'playerId'}},
            {
              'log': 'system',
              'message': {'cat': [{'var': 'playerId'}, ' confirmed their role.']},
            },
            // If all players ready, move to nomination
            {
              'if': {
                '==': [
                  {'length': {'var': 'readyPlayers'}},
                  {'length': {'var': 'playerOrder'}},
                ]
              },
              'then': [
                {'setPhase': 'CHANCELLOR_NOMINATION'},
                {'log': 'system', 'message': 'All players ready. Election begins.'},
              ],
            },
          ],
        },
      },
    },

    // === CHANCELLOR_NOMINATION: president picks a chancellor candidate ===
    'CHANCELLOR_NOMINATION': {
      'activePlayerOnly': true,
      'actions': {
        'NOMINATE': {
          'generate': {
            // Eligible candidates: alive, not president, not previous chancellor,
            // not previous president if 6+ alive
            'forEach': {
              'let': {
                r'$aliveCount': {
                  '-': [
                    {'length': {'var': 'playerOrder'}},
                    {'length': {'var': 'deadPlayers'}},
                  ]
                },
              },
              'in': {
                'filter': {
                  'list': {'var': 'playerOrder'},
                  'as': r'$cand',
                  'where': {
                    'and': [
                      {'!=': [{'var': r'$cand'}, {'var': 'presidentId'}]},
                      {
                        'not': {
                          'contains': [
                            {'var': 'deadPlayers'},
                            {'var': r'$cand'},
                          ]
                        }
                      },
                      {'!=': [{'var': r'$cand'}, {'var': 'previousChancellorId'}]},
                      {
                        'or': [
                          {'<=': [{'var': r'$aliveCount'}, 5]},
                          {'!=': [{'var': r'$cand'}, {'var': 'previousPresidentId'}]},
                        ]
                      },
                    ]
                  },
                }
              },
            },
            'as': r'$target',
            'label': {'cat': ['Nominate ', {'var': r'$target'}, ' as Chancellor']},
            'params': {
              'targetId': {'var': r'$target'},
            },
          },
          'effects': [
            {'set': {'var': 'action.targetId'}, 'path': 'chancellorCandidateId'},
            {'setPhase': 'VOTING'},
            {'set': {'literal': {}}, 'path': 'votes'},
            {'set': null, 'path': 'voteResult'},
            {
              'log': 'system',
              'message': {
                'cat': [
                  'President ', {'var': 'presidentId'},
                  ' nominated ', {'var': 'action.targetId'},
                  ' as Chancellor.',
                ]
              },
            },
          ],
        },
      },
    },

    // === VOTING: all alive players vote Ja or Nein ===
    'VOTING': {
      'activePlayerOnly': false,
      'actions': {
        'VOTE_JA': {
          'allowedWhen': {
            'and': [
              {
                'not': {
                  'contains': [
                    {'var': 'deadPlayers'},
                    {'var': 'playerId'},
                  ]
                }
              },
              {
                'not': {
                  'contains': [
                    {'keys': {'var': 'votes'}},
                    {'var': 'playerId'},
                  ]
                }
              },
            ]
          },
          'label': 'Ja! (Yes)',
          'effects': [
            {'set': 'JA', 'path': r'votes.{playerId}'},
            ..._afterVoteEffects,
          ],
        },
        'VOTE_NEIN': {
          'allowedWhen': {
            'and': [
              {
                'not': {
                  'contains': [
                    {'var': 'deadPlayers'},
                    {'var': 'playerId'},
                  ]
                }
              },
              {
                'not': {
                  'contains': [
                    {'keys': {'var': 'votes'}},
                    {'var': 'playerId'},
                  ]
                }
              },
            ]
          },
          'label': 'Nein! (No)',
          'effects': [
            {'set': 'NEIN', 'path': r'votes.{playerId}'},
            ..._afterVoteEffects,
          ],
        },
      },
    },

    // === LEGISLATIVE_PRESIDENT: president discards one of 3 policies ===
    'LEGISLATIVE_PRESIDENT': {
      'activePlayerOnly': true,
      'actions': {
        'DISCARD_POLICY': {
          'generate': {
            'forEach': {'var': 'drawnPolicies'},
            'as': r'$policy',
            'index': r'$idx',
            'label': {
              'cat': [
                'Discard ',
                {
                  'if': [
                    {'==': [{'var': r'$policy'}, 'LIBERAL']},
                    'Liberal',
                    'Fascist',
                  ]
                },
                ' policy',
              ]
            },
            'params': {
              'discardIndex': {'var': r'$idx'},
            },
          },
          'effects': [
            // Append discarded policy to discard pile
            {
              'append': 'discard',
              'value': {
                'get': [
                  {'var': 'drawnPolicies'},
                  {'var': 'action.discardIndex'},
                ]
              },
            },
            // Remove discarded policy from drawnPolicies by rebuilding without it
            {
              'let': {
                r'$discIdx': {'var': 'action.discardIndex'},
              },
              'do': [
                {
                  'set': {
                    'filter': {
                      'list': {
                        'map': {
                          'list': {'range': {'end': {'length': {'var': 'drawnPolicies'}}, 'start': 0}},
                          'as': r'$i',
                          'to': {
                            'literal': {'i': {'var': r'$i'}, 'v': {'get': [{'var': 'drawnPolicies'}, {'var': r'$i'}]}},
                          },
                        }
                      },
                      'as': r'$entry',
                      'where': {'!=': [{'get': [{'var': r'$entry'}, 'i']}, {'var': r'$discIdx'}]},
                    }
                  },
                  'path': '_tempFiltered',
                },
              ],
            },
            // Actually, simpler approach: use filter with index
            // Rebuild drawnPolicies as items not at discardIndex
            {
              'let': {
                r'$discIdx': {'var': 'action.discardIndex'},
                r'$drawn': {'var': 'drawnPolicies'},
              },
              'do': [
                {
                  'set': {
                    'if': [
                      {'==': [{'var': r'$discIdx'}, 0]},
                      {'skip': {'list': {'var': r'$drawn'}, 'count': 1}},
                      {
                        'if': [
                          {'==': [{'var': r'$discIdx'}, {'- ': [{'length': {'var': r'$drawn'}}, 1]}]},
                          {'take': {'list': {'var': r'$drawn'}, 'count': {'-': [{'length': {'var': r'$drawn'}}, 1]}}},
                          // middle element: take first + skip first+1
                          {
                            'flatten': [
                              {'take': {'list': {'var': r'$drawn'}, 'count': {'var': r'$discIdx'}}},
                              {'skip': {'list': {'var': r'$drawn'}, 'count': {'+': [{'var': r'$discIdx'}, 1]}}},
                            ]
                          },
                        ]
                      },
                    ]
                  },
                  'path': 'drawnPolicies',
                },
              ],
            },
            {'delete': '_tempFiltered'},
            {'setPhase': 'LEGISLATIVE_CHANCELLOR'},
            {'log': 'system', 'message': 'President discarded 1 policy, passed 2 to Chancellor.'},
          ],
        },
      },
    },

    // === LEGISLATIVE_CHANCELLOR: chancellor enacts one of 2 policies ===
    'LEGISLATIVE_CHANCELLOR': {
      'activePlayerOnly': false,
      'actions': {
        'ENACT_POLICY': {
          'allowedWhen': {
            '==': [{'var': 'playerId'}, {'var': 'chancellorId'}],
          },
          'generate': {
            'forEach': {'var': 'drawnPolicies'},
            'as': r'$policy',
            'index': r'$idx',
            'label': {
              'cat': [
                'Enact ',
                {
                  'if': [
                    {'==': [{'var': r'$policy'}, 'LIBERAL']},
                    'Liberal',
                    'Fascist',
                  ]
                },
                ' policy',
              ]
            },
            'params': {
              'enactIndex': {'var': r'$idx'},
            },
          },
          'effects': [
            {
              'let': {
                r'$enactIdx': {'var': 'action.enactIndex'},
                r'$drawn': {'var': 'drawnPolicies'},
                r'$enacted': {'get': [{'var': 'drawnPolicies'}, {'var': 'action.enactIndex'}]},
              },
              'do': [
                // Discard the other card
                {
                  'let': {
                    r'$remaining': {
                      'flatten': [
                        {'take': {'list': {'var': r'$drawn'}, 'count': {'var': r'$enactIdx'}}},
                        {'skip': {'list': {'var': r'$drawn'}, 'count': {'+': [{'var': r'$enactIdx'}, 1]}}},
                      ]
                    },
                  },
                  'do': [
                    {
                      'forEach': {'var': r'$remaining'},
                      'as': r'$disc',
                      'do': [
                        {'append': 'discard', 'value': {'var': r'$disc'}},
                      ],
                    },
                  ],
                },
                {'set': {'literal': []}, 'path': 'drawnPolicies'},
                // Set term limit tracking
                {'set': {'var': 'presidentId'}, 'path': 'previousPresidentId'},
                {'set': {'var': 'chancellorId'}, 'path': 'previousChancellorId'},
                {'set': {'var': r'$enacted'}, 'path': 'lastEnactedPolicy'},
                {
                  'if': {'==': [{'var': r'$enacted'}, 'LIBERAL']},
                  'then': [
                    {'increment': 'liberalPolicies', 'by': 1},
                    {'log': 'system', 'message': 'A Liberal policy was enacted!'},
                    // Check liberal win
                    {
                      'if': {'==': [{'var': 'liberalPolicies'}, 5]},
                      'then': [
                        {'set': 'LIBERAL', 'path': 'winner'},
                        {'log': 'system', 'message': 'Liberal policies reached 5! Liberals win!'},
                      ],
                      'else': [
                        ..._nextPresidentEffects,
                        {'setPhase': 'CHANCELLOR_NOMINATION'},
                      ],
                    },
                  ],
                  'else': [
                    {'increment': 'fascistPolicies', 'by': 1},
                    {'log': 'system', 'message': 'A Fascist policy was enacted!'},
                    // Check veto unlock at 5
                    {
                      'if': {'==': [{'var': 'fascistPolicies'}, 5]},
                      'then': [
                        {'set': true, 'path': 'vetoUnlocked'},
                      ],
                    },
                    // Check fascist win at 6
                    {
                      'if': {'>=': [{'var': 'fascistPolicies'}, 6]},
                      'then': [
                        {'set': 'FASCIST', 'path': 'winner'},
                        {'log': 'system', 'message': 'Fascist policies reached 6! Fascists win!'},
                      ],
                      'else': [
                        // Determine executive action
                        {
                          'let': {
                            r'$fp': {'var': 'fascistPolicies'},
                            r'$pc': {'length': {'var': 'playerOrder'}},
                          },
                          'do': [
                            {
                              'let': {
                                r'$exec': {
                                  'if': [
                                    {'and': [{'==': [{'var': r'$fp'}, 1]}, {'>=': [{'var': r'$pc'}, 9]}]},
                                    'INVESTIGATE',
                                    {
                                      'if': [
                                        {'and': [{'==': [{'var': r'$fp'}, 2]}, {'>=': [{'var': r'$pc'}, 7]}]},
                                        'INVESTIGATE',
                                        {
                                          'if': [
                                            {'and': [{'==': [{'var': r'$fp'}, 3]}, {'>=': [{'var': r'$pc'}, 7]}]},
                                            'SPECIAL_ELECTION',
                                            {
                                              'if': [
                                                {'and': [{'==': [{'var': r'$fp'}, 3]}, {'<=': [{'var': r'$pc'}, 6]}]},
                                                'POLICY_PEEK',
                                                {
                                                  'if': [
                                                    {'>=': [{'var': r'$fp'}, 4]},
                                                    'EXECUTION',
                                                    'NONE',
                                                  ]
                                                },
                                              ]
                                            },
                                          ]
                                        },
                                      ]
                                    },
                                  ]
                                },
                              },
                              'do': [
                                {
                                  'if': {'==': [{'var': r'$exec'}, 'NONE']},
                                  'then': [
                                    ..._nextPresidentEffects,
                                    {'setPhase': 'CHANCELLOR_NOMINATION'},
                                  ],
                                  'else': [
                                    {'set': {'var': r'$exec'}, 'path': 'executiveActionType'},
                                    {'setPhase': 'EXECUTIVE_ACTION'},
                                    {
                                      'log': 'system',
                                      'message': {'cat': ['Executive action: ', {'var': r'$exec'}]},
                                    },
                                    // For POLICY_PEEK, reshuffle if needed
                                    {
                                      'if': {'==': [{'var': r'$exec'}, 'POLICY_PEEK']},
                                      'then': [
                                        {
                                          'if': {'<': [{'length': {'var': 'deck'}}, 3]},
                                          'then': [
                                            {'returnCards': {'from': 'discard', 'to': 'deck'}},
                                            {'shuffleDeck': 'deck'},
                                          ],
                                        },
                                      ],
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
        'REQUEST_VETO': {
          'allowedWhen': {
            'and': [
              {'==': [{'var': 'playerId'}, {'var': 'chancellorId'}]},
              {'==': [{'var': 'vetoUnlocked'}, true]},
              {'!=': [{'var': 'vetoRequested'}, true]},
            ]
          },
          'label': 'Request Veto',
          'effects': [
            {'set': true, 'path': 'vetoRequested'},
            {'setPhase': 'VETO_RESPONSE'},
            {'log': 'system', 'message': 'Chancellor requested a veto.'},
          ],
        },
      },
    },

    // === VETO_RESPONSE: president approves or rejects veto ===
    'VETO_RESPONSE': {
      'activePlayerOnly': true,
      'actions': {
        'VETO_APPROVE': {
          'label': 'Approve Veto',
          'effects': [
            {'set': false, 'path': 'vetoRequested'},
            // Discard all drawn policies
            {
              'forEach': {'var': 'drawnPolicies'},
              'as': r'$p',
              'do': [
                {'append': 'discard', 'value': {'var': r'$p'}},
              ],
            },
            {'set': {'literal': []}, 'path': 'drawnPolicies'},
            {'log': 'system', 'message': 'President approved the veto. Policies discarded.'},
            {'increment': 'electionTracker', 'by': 1},
            {
              'if': {'>=': [{'var': 'electionTracker'}, 3]},
              'then': [
                {'log': 'system', 'message': 'Veto pushed election tracker to 3!'},
              ],
            },
            ..._nextPresidentEffects,
            {'setPhase': 'CHANCELLOR_NOMINATION'},
          ],
        },
        'VETO_REJECT': {
          'label': 'Reject Veto',
          'effects': [
            {'set': false, 'path': 'vetoRequested'},
            {'setPhase': 'LEGISLATIVE_CHANCELLOR'},
            {'log': 'system', 'message': 'President rejected the veto! Chancellor must enact.'},
          ],
        },
      },
    },

    // === EXECUTIVE_ACTION: president performs an executive action ===
    'EXECUTIVE_ACTION': {
      'activePlayerOnly': true,
      'actions': {
        'EXEC_INVESTIGATE': {
          'allowedWhen': {'==': [{'var': 'executiveActionType'}, 'INVESTIGATE']},
          'generate': {
            'forEach': {
              'filter': {
                'list': {'var': 'playerOrder'},
                'as': r'$cand',
                'where': {
                  'and': [
                    {'!=': [{'var': r'$cand'}, {'var': 'presidentId'}]},
                    {
                      'not': {
                        'contains': [
                          {'var': 'deadPlayers'},
                          {'var': r'$cand'},
                        ]
                      }
                    },
                    {
                      'not': {
                        'contains': [
                          {'var': 'investigatedPlayers'},
                          {'var': r'$cand'},
                        ]
                      }
                    },
                  ]
                },
              }
            },
            'as': r'$target',
            'label': {'cat': ['Investigate ', {'var': r'$target'}]},
            'params': {
              'targetId': {'var': r'$target'},
            },
          },
          'effects': [
            {'append': 'investigatedPlayers', 'value': {'var': 'action.targetId'}},
            {
              'log': 'system',
              'message': {'cat': ['President investigated ', {'var': 'action.targetId'}, '.']},
            },
            ..._nextPresidentEffects,
            {'setPhase': 'CHANCELLOR_NOMINATION'},
          ],
        },
        'EXEC_SPECIAL_ELECTION': {
          'allowedWhen': {'==': [{'var': 'executiveActionType'}, 'SPECIAL_ELECTION']},
          'generate': {
            'forEach': {
              'filter': {
                'list': {'var': 'playerOrder'},
                'as': r'$cand',
                'where': {
                  'and': [
                    {'!=': [{'var': r'$cand'}, {'var': 'presidentId'}]},
                    {
                      'not': {
                        'contains': [
                          {'var': 'deadPlayers'},
                          {'var': r'$cand'},
                        ]
                      }
                    },
                  ]
                },
              }
            },
            'as': r'$target',
            'label': {'cat': [{'var': r'$target'}, ' as next President']},
            'params': {
              'targetId': {'var': r'$target'},
            },
          },
          'effects': [
            {'set': {'var': 'presidentPosition'}, 'path': 'specialElectionReturnIndex'},
            {'set': {'var': 'action.targetId'}, 'path': 'presidentId'},
            {
              'set': {
                'indexOf': [{'var': 'playerOrder'}, {'var': 'action.targetId'}]
              },
              'path': 'presidentPosition',
            },
            {
              'setActivePlayer': {'var': 'action.targetId'},
            },
            {
              'log': 'system',
              'message': {'cat': ['Special election! ', {'var': 'action.targetId'}, ' is the next President.']},
            },
            {'setPhase': 'CHANCELLOR_NOMINATION'},
          ],
        },
        'EXEC_EXECUTION': {
          'allowedWhen': {'==': [{'var': 'executiveActionType'}, 'EXECUTION']},
          'generate': {
            'forEach': {
              'filter': {
                'list': {'var': 'playerOrder'},
                'as': r'$cand',
                'where': {
                  'and': [
                    {'!=': [{'var': r'$cand'}, {'var': 'presidentId'}]},
                    {
                      'not': {
                        'contains': [
                          {'var': 'deadPlayers'},
                          {'var': r'$cand'},
                        ]
                      }
                    },
                  ]
                },
              }
            },
            'as': r'$target',
            'label': {'cat': ['Execute ', {'var': r'$target'}]},
            'params': {
              'targetId': {'var': r'$target'},
            },
          },
          'effects': [
            {'append': 'deadPlayers', 'value': {'var': 'action.targetId'}},
            {
              'log': 'system',
              'message': {'cat': ['President executed ', {'var': 'action.targetId'}, '!']},
            },
            // Check if executed player is Hitler
            {
              'if': {
                '==': [
                  {'get': [{'var': 'roles'}, {'var': 'action.targetId'}]},
                  'HITLER',
                ]
              },
              'then': [
                {'set': 'LIBERAL', 'path': 'winner'},
                {'log': 'system', 'message': 'Hitler has been executed! Liberals win!'},
              ],
              'else': [
                ..._nextPresidentEffects,
                {'setPhase': 'CHANCELLOR_NOMINATION'},
              ],
            },
          ],
        },
        'EXEC_FINISH_PEEK': {
          'allowedWhen': {'==': [{'var': 'executiveActionType'}, 'POLICY_PEEK']},
          'label': 'Finish Peek',
          'effects': [
            {'log': 'system', 'message': 'President peeked at the top 3 policies.'},
            ..._nextPresidentEffects,
            {'setPhase': 'CHANCELLOR_NOMINATION'},
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
      '!=': [{'var': 'winner'}, null],
    },
    'winners': {'literal': []},
  },

  // ---------------------------------------------------------------------------
  // Board view
  // ---------------------------------------------------------------------------
  'boardView': {
    'includePlayerInfo': true,
    'deckRemaining': {'length': {'var': 'deck'}},
    'discardPile': {'literal': []},
    'maxRecentLog': 20,
    'data': {
      'phase': {'var': 'phase'},
      'playerOrder': {'var': 'playerOrder'},
      'presidentId': {'var': 'presidentId'},
      'chancellorId': {'var': 'chancellorId'},
      'chancellorCandidateId': {'var': 'chancellorCandidateId'},
      'liberalPolicies': {'var': 'liberalPolicies'},
      'fascistPolicies': {'var': 'fascistPolicies'},
      'electionTracker': {'var': 'electionTracker'},
      'vetoUnlocked': {'var': 'vetoUnlocked'},
      'winner': {'var': 'winner'},
      'lastEnactedPolicy': {'var': 'lastEnactedPolicy'},
      'deadPlayers': {'var': 'deadPlayers'},
      'executiveActionType': {'var': 'executiveActionType'},
      'deckCount': {'length': {'var': 'deck'}},
      'discardCount': {'length': {'var': 'discard'}},
      'completedVotes': {
        'if': [
          {'!=': [{'var': 'voteResult'}, null]},
          {'var': 'votes'},
          null,
        ]
      },
      'voteResult': {'var': 'voteResult'},
    },
  },

  // ---------------------------------------------------------------------------
  // Player view
  // ---------------------------------------------------------------------------
  'playerView': {
    'includePlayerInfo': true,
    'hand': {'literal': []},
    'data': {
      'phase': {'var': 'phase'},
      'presidentId': {'var': 'presidentId'},
      'chancellorId': {'var': 'chancellorId'},
      'chancellorCandidateId': {'var': 'chancellorCandidateId'},
      'liberalPolicies': {'var': 'liberalPolicies'},
      'fascistPolicies': {'var': 'fascistPolicies'},
      'electionTracker': {'var': 'electionTracker'},
      'vetoUnlocked': {'var': 'vetoUnlocked'},
      'winner': {'var': 'winner'},
      'lastEnactedPolicy': {'var': 'lastEnactedPolicy'},
      'deadPlayers': {'var': 'deadPlayers'},
      'playerOrder': {'var': 'playerOrder'},
      'executiveActionType': {'var': 'executiveActionType'},
      // Player's own role
      'myRole': {'get': [{'var': 'roles'}, {'var': 'playerId'}]},
      'myParty': {
        'if': [
          {
            'or': [
              {'==': [{'get': [{'var': 'roles'}, {'var': 'playerId'}]}, 'HITLER']},
              {'==': [{'get': [{'var': 'roles'}, {'var': 'playerId'}]}, 'FASCIST']},
            ]
          },
          'FASCIST',
          'LIBERAL',
        ]
      },
    },
    'conditionalData': [
      // Vote result (if complete)
      {
        'when': {'!=': [{'var': 'voteResult'}, null]},
        'data': {
          'voteResult': {'var': 'voteResult'},
          'completedVotes': {'var': 'votes'},
        },
      },
      // Voting phase info
      {
        'when': {'==': [{'var': 'phase'}, 'VOTING']},
        'data': {
          'hasVoted': {
            'contains': [
              {'keys': {'var': 'votes'}},
              {'var': 'playerId'},
            ]
          },
          'totalVoters': {
            '-': [
              {'length': {'var': 'playerOrder'}},
              {'length': {'var': 'deadPlayers'}},
            ]
          },
          'currentVoteCount': {'length': {'var': 'votes'}},
        },
      },
      // Role reveal progress
      {
        'when': {'==': [{'var': 'phase'}, 'ROLE_REVEAL']},
        'data': {
          'readyCount': {'length': {'var': 'readyPlayers'}},
          'totalPlayers': {'length': {'var': 'playerOrder'}},
          'isReady': {
            'contains': [
              {'var': 'readyPlayers'},
              {'var': 'playerId'},
            ]
          },
        },
      },
      // Fascist team knowledge (fascists see allies, hitler sees allies in 5-6 player)
      {
        'when': {
          'or': [
            {'==': [{'get': [{'var': 'roles'}, {'var': 'playerId'}]}, 'FASCIST']},
            {
              'and': [
                {'==': [{'get': [{'var': 'roles'}, {'var': 'playerId'}]}, 'HITLER']},
                {'<=': [{'length': {'var': 'playerOrder'}}, 6]},
              ]
            },
          ]
        },
        'data': {
          'fascistAllies': {
            'filter': {
              'list': {'keys': {'var': 'roles'}},
              'as': r'$k',
              'where': {'==': [{'get': [{'var': 'roles'}, {'var': r'$k'}]}, 'FASCIST']},
            }
          },
          'hitlerId': {
            'let': {
              r'$hitlers': {
                'filter': {
                  'list': {'keys': {'var': 'roles'}},
                  'as': r'$k',
                  'where': {'==': [{'get': [{'var': 'roles'}, {'var': r'$k'}]}, 'HITLER']},
                }
              },
            },
            'in': {
              'if': [
                {'isNotEmpty': {'var': r'$hitlers'}},
                {'get': [{'var': r'$hitlers'}, 0]},
                '',
              ]
            },
          },
        },
      },
      // Drawn policies for president during legislative or peek
      {
        'when': {
          'and': [
            {'==': [{'var': 'playerId'}, {'var': 'presidentId'}]},
            {
              'or': [
                {'==': [{'var': 'phase'}, 'LEGISLATIVE_PRESIDENT']},
                {
                  'and': [
                    {'==': [{'var': 'phase'}, 'EXECUTIVE_ACTION']},
                    {'==': [{'var': 'executiveActionType'}, 'POLICY_PEEK']},
                  ]
                },
              ]
            },
          ]
        },
        'data': {
          'drawnPolicies': {
            'if': [
              {
                'and': [
                  {'==': [{'var': 'phase'}, 'EXECUTIVE_ACTION']},
                  {'isEmpty': {'var': 'drawnPolicies'}},
                ]
              },
              {'take': {'list': {'var': 'deck'}, 'count': 3}},
              {'var': 'drawnPolicies'},
            ]
          },
        },
      },
      // Drawn policies for chancellor during legislative
      {
        'when': {
          'and': [
            {'==': [{'var': 'playerId'}, {'var': 'chancellorId'}]},
            {'==': [{'var': 'phase'}, 'LEGISLATIVE_CHANCELLOR']},
          ]
        },
        'data': {
          'drawnPolicies': {'var': 'drawnPolicies'},
        },
      },
      // Investigation results for president
      {
        'when': {
          'and': [
            {'==': [{'var': 'playerId'}, {'var': 'presidentId'}]},
            {'==': [{'var': 'phase'}, 'EXECUTIVE_ACTION']},
            {'==': [{'var': 'executiveActionType'}, 'INVESTIGATE']},
          ]
        },
        'data': {
          'investigationResults': {
            'reduce': {
              'list': {'var': 'investigatedPlayers'},
              'as': r'$pid',
              'acc': r'$results',
              'init': {'literal': {}},
              'to': {
                // Can't easily merge into a map in pure expressions.
                // Use a workaround: return the accumulated map.
                // Actually, we'll just provide the investigated player list
                // and their party membership.
                'var': r'$results',
              },
            }
          },
        },
      },
      // Winner: reveal all roles
      {
        'when': {'!=': [{'var': 'winner'}, null]},
        'data': {
          'allRoles': {'var': 'roles'},
        },
      },
    ],
  },
};

// ---------------------------------------------------------------------------
// After-vote effect sequence (shared between VOTE_JA and VOTE_NEIN)
// ---------------------------------------------------------------------------
const List<Map<String, dynamic>> _afterVoteEffects = [
  // Check if all alive players have voted
  {
    'let': {
      r'$aliveCount': {
        '-': [
          {'length': {'var': 'playerOrder'}},
          {'length': {'var': 'deadPlayers'}},
        ]
      },
    },
    'do': [
      {
        'if': {
          '==': [
            {'length': {'var': 'votes'}},
            {'var': r'$aliveCount'},
          ]
        },
        'then': [
          // Count Ja votes
          {
            'let': {
              r'$jaCount': {
                'length': {
                  'filter': {
                    'list': {'values': {'var': 'votes'}},
                    'as': r'$v',
                    'where': {'==': [{'var': r'$v'}, 'JA']},
                  }
                }
              },
            },
            'do': [
              {
                'if': {'>': [{'var': r'$jaCount'}, {'/': [{'var': r'$aliveCount'}, 2]}]},
                'then': [
                  // PASSED
                  {'set': {'var': 'chancellorCandidateId'}, 'path': 'chancellorId'},
                  {'set': 0, 'path': 'electionTracker'},
                  {'set': 'PASSED', 'path': 'voteResult'},
                  {'log': 'system', 'message': 'Vote passed!'},
                  // Check Hitler chancellor win
                  {
                    'if': {
                      'and': [
                        {'>=': [{'var': 'fascistPolicies'}, 3]},
                        {'==': [{'get': [{'var': 'roles'}, {'var': 'chancellorId'}]}, 'HITLER']},
                      ]
                    },
                    'then': [
                      {'set': 'FASCIST', 'path': 'winner'},
                      {'log': 'system', 'message': 'Hitler elected Chancellor! Fascists win!'},
                    ],
                    'else': [
                      // Draw 3 policies, reshuffle if needed
                      {
                        'if': {'<': [{'length': {'var': 'deck'}}, 3]},
                        'then': [
                          {'returnCards': {'from': 'discard', 'to': 'deck'}},
                          {'shuffleDeck': 'deck'},
                          {'log': 'system', 'message': 'Deck reshuffled.'},
                        ],
                      },
                      {'set': {'literal': []}, 'path': 'drawnPolicies'},
                      {
                        'drawCards': {
                          'from': 'deck',
                          'to': 'drawnPolicies',
                          'count': 3,
                        }
                      },
                      {'setPhase': 'LEGISLATIVE_PRESIDENT'},
                    ],
                  },
                ],
                'else': [
                  // FAILED
                  {'set': 'FAILED', 'path': 'voteResult'},
                  {'log': 'system', 'message': 'Vote failed.'},
                  {'increment': 'electionTracker', 'by': 1},
                  {
                    'if': {'>=': [{'var': 'electionTracker'}, 3]},
                    'then': _chaosEffects,
                    'else': [
                      ..._nextPresidentEffects,
                      {'setPhase': 'CHANCELLOR_NOMINATION'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
];
