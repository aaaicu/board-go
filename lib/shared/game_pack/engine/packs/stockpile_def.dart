import '../pack_definition.dart';

/// Returns the JSON DSL pack definition for Stockpile.
PackDefinition stockpileDefinition() {
  return PackDefinition.fromJson(_buildDefinition());
}

// ─── Constants ──────────────────────────────────────────────────────────────

const _kCompanies = ['aauto', 'epic', 'fed', 'lehm', 'sip', 'tot'];
const _kDividendSentinel = -99;
const _kMaxBid = 25000;
const _kStockLookup = <String, String>{
  'stock_aauto': 'aauto',
  'stock_epic': 'epic',
  'stock_fed': 'fed',
  'stock_lehm': 'lehm',
  'stock_sip': 'sip',
  'stock_tot': 'tot',
};

// ─── Expression helpers ─────────────────────────────────────────────────────

/// Safe access: portfolios[pid][company] ?? 0
Map<String, dynamic> _portfolioShares(String pidVar, String companyVar) => {
  'if': [
    {'get': [{'get': [{'var': 'portfolios'}, {'var': pidVar}]}, {'var': companyVar}]},
    {'get': [{'get': [{'var': 'portfolios'}, {'var': pidVar}]}, {'var': companyVar}]},
    0,
  ],
};

/// Safe access: splitPortfolios[pid][company] ?? 0
Map<String, dynamic> _splitShares(String pidVar, String companyVar) => {
  'if': [
    {'get': [{'get': [{'var': 'splitPortfolios'}, {'var': pidVar}]}, {'var': companyVar}]},
    {'get': [{'get': [{'var': 'splitPortfolios'}, {'var': pidVar}]}, {'var': companyVar}]},
    0,
  ],
};

/// Safe access: cash[pid] ?? 0
Map<String, dynamic> _cashOf(String pidVar) => {
  'if': [
    {'get': [{'var': 'cash'}, {'var': pidVar}]},
    {'get': [{'var': 'cash'}, {'var': pidVar}]},
    0,
  ],
};

/// Safe access: stockPrices[company] ?? 0
Map<String, dynamic> _priceOf(String companyVar) => {
  'if': [
    {'get': [{'var': 'stockPrices'}, {'var': companyVar}]},
    {'get': [{'var': 'stockPrices'}, {'var': companyVar}]},
    0,
  ],
};

// ─── Effect helpers ─────────────────────────────────────────────────────────

/// Transition to [phase], reset acted list, activate first player.
List<Map<String, dynamic>> _transitionToPhase(String phase) => [
  {'setPhase': phase},
  {'set': {'literal': []}, 'path': 'phaseActedPlayers'},
  {'setActivePlayer': {'get': [{'var': 'playerOrder'}, 0]}},
  {
    'setTurn': {
      'turnIndex': 0,
      'activePlayerId': {'get': [{'var': 'playerOrder'}, 0]},
      'actionCountThisTurn': 0,
    },
  },
];

/// Add current player to phaseActedPlayers, find next unacted player.
/// If found → set active. If all done → run [transitionEffects].
List<Map<String, dynamic>> _advanceOrTransition(
  List<Map<String, dynamic>> transitionEffects,
) =>
    [
      {
        'if': {
          'not': {
            'contains': [
              {'var': 'phaseActedPlayers'},
              {'var': 'playerId'},
            ],
          },
        },
        'then': [
          {'append': 'phaseActedPlayers', 'value': {'var': 'playerId'}},
        ],
      },
      {
        'let': {
          r'$unacted': {
            'filter': {
              'list': {'var': 'playerOrder'},
              'as': r'$p',
              'where': {
                'not': {
                  'contains': [
                    {'var': 'phaseActedPlayers'},
                    {'var': r'$p'},
                  ],
                },
              },
            },
          },
        },
        'do': [
          {
            'if': {
              'isNotEmpty': {'var': r'$unacted'},
            },
            'then': [
              {
                'setActivePlayer': {'get': [{'var': r'$unacted'}, 0]},
              },
              {
                'setTurn': {
                  'turnIndex': {
                    'indexOf': [
                      {'var': 'playerOrder'},
                      {'get': [{'var': r'$unacted'}, 0]},
                    ],
                  },
                  'activePlayerId': {'get': [{'var': r'$unacted'}, 0]},
                  'actionCountThisTurn': 0,
                },
              },
            ],
            'else': transitionEffects,
          },
        ],
      },
    ];

/// Supply cross-product generate: card × stockpile
Map<String, dynamic> _supplyGenerate() => {
  'forEach': {
    'range': {
      '*': [
        {'length': {'var': r'supplyHands.{playerId}'}},
        {'length': {'var': 'stockpiles'}},
      ],
    },
  },
  'as': r'$fi',
  'label': {
    'cat': [
      'Place ',
      {
        'get': [
          {'var': r'supplyHands.{playerId}'},
          {'toInt': {'/': [{'var': r'$fi'}, {'length': {'var': 'stockpiles'}}]}},
        ],
      },
      ' on pile ',
      {'+': [{'%': [{'var': r'$fi'}, {'length': {'var': 'stockpiles'}}]}, 1]},
    ],
  },
  'params': {
    'cardIndex': {
      'toInt': {'/': [{'var': r'$fi'}, {'length': {'var': 'stockpiles'}}]},
    },
    'stockpileIndex': {'%': [{'var': r'$fi'}, {'length': {'var': 'stockpiles'}}]},
  },
};

/// Effects after placing a supply card: check if both placed → advance.
List<Map<String, dynamic>> _supplyCheckAdvanceEffects() => [
  {
    'if': {
      'and': [
        {'var': r'supplyPlaced.{playerId}.faceUp'},
        {'var': r'supplyPlaced.{playerId}.faceDown'},
      ],
    },
    'then': _advanceOrTransition(_transitionToPhase('demand')),
  },
];

/// Demand phase advance — handles first round and rebid rounds.
List<Map<String, dynamic>> _demandAdvanceEffects() => [
  {
    'if': {'==': [{'var': 'demandRound'}, 1]},
    'then': [
      // Round 1: sequential through all players
      {
        'if': {
          'not': {
            'contains': [
              {'var': 'phaseActedPlayers'},
              {'var': 'playerId'},
            ],
          },
        },
        'then': [
          {'append': 'phaseActedPlayers', 'value': {'var': 'playerId'}},
        ],
      },
      {
        'let': {
          r'$unacted': {
            'filter': {
              'list': {'var': 'playerOrder'},
              'as': r'$p',
              'where': {
                'not': {
                  'contains': [
                    {'var': 'phaseActedPlayers'},
                    {'var': r'$p'},
                  ],
                },
              },
            },
          },
        },
        'do': [
          {
            'if': {'isNotEmpty': {'var': r'$unacted'}},
            'then': [
              {'setActivePlayer': {'get': [{'var': r'$unacted'}, 0]}},
              {
                'setTurn': {
                  'turnIndex': {
                    'indexOf': [
                      {'var': 'playerOrder'},
                      {'get': [{'var': r'$unacted'}, 0]},
                    ],
                  },
                  'activePlayerId': {'get': [{'var': r'$unacted'}, 0]},
                  'actionCountThisTurn': 0,
                },
              },
            ],
            'else': [
              // All bid once — check for outbids
              {
                'if': {'isEmpty': {'var': 'outbidPlayers'}},
                'then': [
                  ..._resolveBidsEffects(),
                  ..._transitionToPhase('action'),
                ],
                'else': _startRebidRoundEffects(),
              },
            ],
          },
        ],
      },
    ],
    'else': [
      // Rebid round
      {
        'if': {
          'not': {
            'contains': [
              {'var': 'rebidActedPlayers'},
              {'var': 'playerId'},
            ],
          },
        },
        'then': [
          {'append': 'rebidActedPlayers', 'value': {'var': 'playerId'}},
        ],
      },
      {
        'let': {
          r'$nextRebid': {
            'filter': {
              'list': {'var': 'playerOrder'},
              'as': r'$p',
              'where': {
                'and': [
                  {
                    'contains': [
                      {'var': 'outbidPlayers'},
                      {'var': r'$p'},
                    ],
                  },
                  {
                    'not': {
                      'contains': [
                        {'var': 'rebidActedPlayers'},
                        {'var': r'$p'},
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
        'do': [
          {
            'if': {'isNotEmpty': {'var': r'$nextRebid'}},
            'then': [
              {'setActivePlayer': {'get': [{'var': r'$nextRebid'}, 0]}},
              {
                'setTurn': {
                  'turnIndex': {
                    'indexOf': [
                      {'var': 'playerOrder'},
                      {'get': [{'var': r'$nextRebid'}, 0]},
                    ],
                  },
                  'activePlayerId': {'get': [{'var': r'$nextRebid'}, 0]},
                  'actionCountThisTurn': 0,
                },
              },
            ],
            'else': [
              // All acted this rebid round
              {
                'let': {
                  r'$allPassed': {
                    'or': [
                      {'isEmpty': {'var': 'outbidPlayers'}},
                      {
                        '==': [
                          {
                            'length': {
                              'filter': {
                                'list': {'var': 'outbidPlayers'},
                                'as': r'$op',
                                'where': {
                                  'contains': [
                                    {'var': 'demandPassedPlayers'},
                                    {'var': r'$op'},
                                  ],
                                },
                              },
                            },
                          },
                          {'length': {'var': 'outbidPlayers'}},
                        ],
                      },
                    ],
                  },
                },
                'do': [
                  {
                    'if': {'var': r'$allPassed'},
                    'then': [
                      ..._resolveBidsEffects(),
                      ..._transitionToPhase('action'),
                    ],
                    'else': _startRebidRoundEffects(),
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

/// Start a new rebid round.
List<Map<String, dynamic>> _startRebidRoundEffects() => [
  {'increment': 'demandRound', 'by': 1},
  {'set': {'literal': []}, 'path': 'rebidActedPlayers'},
  {'set': {'literal': []}, 'path': 'demandPassedPlayers'},
  {
    'let': {
      r'$firstOutbid': {
        'get': [
          {
            'filter': {
              'list': {'var': 'playerOrder'},
              'as': r'$p',
              'where': {
                'contains': [
                  {'var': 'outbidPlayers'},
                  {'var': r'$p'},
                ],
              },
            },
          },
          0,
        ],
      },
    },
    'do': [
      {'setActivePlayer': {'var': r'$firstOutbid'}},
      {
        'setTurn': {
          'turnIndex': {
            'indexOf': [
              {'var': 'playerOrder'},
              {'var': r'$firstOutbid'},
            ],
          },
          'activePlayerId': {'var': r'$firstOutbid'},
          'actionCountThisTurn': 0,
        },
      },
    ],
  },
];

/// Resolve all bids: distribute stockpile cards to winners/unclaimed.
List<Map<String, dynamic>> _resolveBidsEffects() => [
  // Track winners
  {'set': {'literal': []}, 'path': '_resolveWinners'},

  // Process stockpiles with winners
  {
    'forEach': {'var': 'stockpiles'},
    'as': r'$sp',
    'index': r'$spIdx',
    'do': [
      {
        'let': {
          r'$winner': {'var': r'$sp.currentBidderId'},
          r'$bidAmount': {
            'if': [{'var': r'$sp.currentBid'}, {'var': r'$sp.currentBid'}, 0],
          },
        },
        'do': [
          {
            'if': {'!=': [{'var': r'$winner'}, null]},
            'then': [
              // Add to winners
              {
                'if': {
                  'not': {
                    'contains': [
                      {'var': '_resolveWinners'},
                      {'var': r'$winner'},
                    ],
                  },
                },
                'then': [
                  {'append': '_resolveWinners', 'value': {'var': r'$winner'}},
                ],
              },
              // Deduct bid
              {
                'increment': r'cash.{$winner}',
                'by': {'-': [0, {'var': r'$bidAmount'}]},
              },
              // Process cards
              {
                'let': {
                  r'$allCards': {
                    'flatten': [
                      {
                        'if': [
                          {'var': r'$sp.faceUpCards'},
                          {'var': r'$sp.faceUpCards'},
                          {'literal': []},
                        ],
                      },
                      {
                        'if': [
                          {'var': r'$sp.faceDownCards'},
                          {'var': r'$sp.faceDownCards'},
                          {'literal': []},
                        ],
                      },
                    ],
                  },
                },
                'do': [
                  {
                    'forEach': {'var': r'$allCards'},
                    'as': r'$card',
                    'do': _processWonCardEffects(r'$winner'),
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },

  // Assign unclaimed stockpiles to players without wins
  {
    'let': {
      r'$noWinPlayers': {
        'filter': {
          'list': {'var': 'playerOrder'},
          'as': r'$p',
          'where': {
            'not': {
              'contains': [
                {'var': '_resolveWinners'},
                {'var': r'$p'},
              ],
            },
          },
        },
      },
      r'$unclaimedIndices': {
        'filter': {
          'list': {
            'range': {'length': {'var': 'stockpiles'}},
          },
          'as': r'$idx',
          'where': {
            '==': [
              {
                'get': [
                  {'get': [{'var': 'stockpiles'}, {'var': r'$idx'}]},
                  'currentBidderId',
                ],
              },
              null,
            ],
          },
        },
      },
    },
    'do': [
      {
        'let': {
          r'$pairCount': {
            'min': [
              {'length': {'var': r'$noWinPlayers'}},
              {'length': {'var': r'$unclaimedIndices'}},
            ],
          },
        },
        'do': [
          {
            'forEach': {'range': {'var': r'$pairCount'}},
            'as': r'$i',
            'do': [
              {
                'let': {
                  r'$pid': {
                    'get': [{'var': r'$noWinPlayers'}, {'var': r'$i'}],
                  },
                  r'$ucSpIdx': {
                    'get': [{'var': r'$unclaimedIndices'}, {'var': r'$i'}],
                  },
                },
                'do': [
                  {
                    'let': {
                      r'$ucSp': {
                        'get': [{'var': 'stockpiles'}, {'var': r'$ucSpIdx'}],
                      },
                    },
                    'do': [
                      {
                        'let': {
                          r'$allCards': {
                            'flatten': [
                              {
                                'if': [
                                  {'var': r'$ucSp.faceUpCards'},
                                  {'var': r'$ucSp.faceUpCards'},
                                  {'literal': []},
                                ],
                              },
                              {
                                'if': [
                                  {'var': r'$ucSp.faceDownCards'},
                                  {'var': r'$ucSp.faceDownCards'},
                                  {'literal': []},
                                ],
                              },
                            ],
                          },
                        },
                        'do': [
                          {
                            'forEach': {'var': r'$allCards'},
                            'as': r'$card',
                            'do': _processUnclaimedCardEffects(r'$pid'),
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

  // Cleanup temp
  {'delete': '_resolveWinners'},
];

/// Process a single card from a won stockpile.
/// [winnerVar] is the local variable name holding the winner's player ID.
List<Map<String, dynamic>> _processWonCardEffects(String winnerVar) => [
  {
    'if': {'==': [{'var': r'$card'}, 'fee_1000']},
    'then': [
      {
        'if': {'>=': [{'var': 'cash.{$winnerVar}'}, 1000]},
        'then': [{'increment': 'cash.{$winnerVar}', 'by': -1000}],
        'else': [{'increment': 'pendingFees.{$winnerVar}', 'by': 1000}],
      },
    ],
    'else': [
      {
        'if': {'==': [{'var': r'$card'}, 'fee_2000']},
        'then': [
          {
            'if': {'>=': [{'var': 'cash.{$winnerVar}'}, 2000]},
            'then': [{'increment': 'cash.{$winnerVar}', 'by': -2000}],
            'else': [{'increment': 'pendingFees.{$winnerVar}', 'by': 2000}],
          },
        ],
        'else': [
          {
            'if': {'==': [{'var': r'$card'}, 'action_boom']},
            'then': [
              {'append': 'actionCards.{$winnerVar}', 'value': 'action_boom'},
            ],
            'else': [
              {
                'if': {'==': [{'var': r'$card'}, 'action_bust']},
                'then': [
                  {
                    'append': 'actionCards.{$winnerVar}',
                    'value': 'action_bust',
                  },
                ],
                'else': [
                  // Stock card → portfolio
                  {
                    'let': {
                      r'$company': {
                        'get': [{'literal': _kStockLookup}, {'var': r'$card'}],
                      },
                    },
                    'do': [
                      {
                        'if': {'!=': [{'var': r'$company'}, null]},
                        'then': [
                          {
                            'increment':
                                'portfolios.{$winnerVar}.{\$company}',
                            'by': 1,
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
];

/// Process a card from an unclaimed stockpile (fees ignored).
List<Map<String, dynamic>> _processUnclaimedCardEffects(String pidVar) => [
  {
    'if': {
      'in': [
        {'var': r'$card'},
        {'literal': ['fee_1000', 'fee_2000']},
      ],
    },
    'then': [{'noop': true}],
    'else': [
      {
        'if': {'==': [{'var': r'$card'}, 'action_boom']},
        'then': [
          {'append': 'actionCards.{$pidVar}', 'value': 'action_boom'},
        ],
        'else': [
          {
            'if': {'==': [{'var': r'$card'}, 'action_bust']},
            'then': [
              {'append': 'actionCards.{$pidVar}', 'value': 'action_bust'},
            ],
            'else': [
              {
                'let': {
                  r'$company': {
                    'get': [{'literal': _kStockLookup}, {'var': r'$card'}],
                  },
                },
                'do': [
                  {
                    'if': {'!=': [{'var': r'$company'}, null]},
                    'then': [
                      {
                        'increment': 'portfolios.{$pidVar}.{\$company}',
                        'by': 1,
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
];

/// Split consequences: existing splits → cash out $10K each, normal → split.
List<Map<String, dynamic>> _splitConsequenceEffects() => [
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$pid',
    'do': [
      // Cash out existing split shares at $10K each
      {
        'let': {
          r'$existingSplit': _splitShares(r'$pid', r'$company'),
        },
        'do': [
          {
            'if': {'>': [{'var': r'$existingSplit'}, 0]},
            'then': [
              {
                'increment': r'cash.{$pid}',
                'by': {'*': [{'var': r'$existingSplit'}, 10000]},
              },
              {'set': 0, 'path': r'splitPortfolios.{$pid}.{$company}'},
            ],
          },
        ],
      },
      // Move normal shares to split portfolio
      {
        'let': {
          r'$normalShares': _portfolioShares(r'$pid', r'$company'),
        },
        'do': [
          {
            'if': {'>': [{'var': r'$normalShares'}, 0]},
            'then': [
              {
                'increment': r'splitPortfolios.{$pid}.{$company}',
                'by': {'var': r'$normalShares'},
              },
              {'set': 0, 'path': r'portfolios.{$pid}.{$company}'},
            ],
          },
        ],
      },
    ],
  },
];

/// Bankruptcy: wipe all shares of company.
List<Map<String, dynamic>> _bankruptcyConsequenceEffects() => [
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$pid',
    'do': [
      {'set': 0, 'path': r'portfolios.{$pid}.{$company}'},
      {'set': 0, 'path': r'splitPortfolios.{$pid}.{$company}'},
    ],
  },
];

/// Dividend: pay $2,000 per effective share (split counts ×2).
List<Map<String, dynamic>> _dividendEffects() => [
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$pid',
    'do': [
      {
        'let': {
          r'$normal': _portfolioShares(r'$pid', r'$company'),
          r'$split': _splitShares(r'$pid', r'$company'),
        },
        'do': [
          {
            'let': {
              r'$dividend': {
                '*': [
                  {'+': [{'var': r'$normal'}, {'*': [{'var': r'$split'}, 2]}]},
                  2000,
                ],
              },
            },
            'do': [
              {
                'if': {'>': [{'var': r'$dividend'}, 0]},
                'then': [
                  {'increment': r'cash.{$pid}', 'by': {'var': r'$dividend'}},
                ],
              },
            ],
          },
        ],
      },
    ],
  },
  {
    'log': 'DIVIDEND',
    'message': {'cat': [{'var': r'$company'}, ' dividend paid']},
  },
];

/// Price change with split/bankruptcy mechanics.
/// Expects $company and $change in scope.
List<Map<String, dynamic>> _priceChangeEffects() => [
  {
    'let': {
      r'$currentPrice': {'var': r'stockPrices.{$company}'},
      r'$newPrice': {
        '+': [{'var': r'stockPrices.{$company}'}, {'var': r'$change'}],
      },
    },
    'do': [
      {
        'if': {'>': [{'var': r'$newPrice'}, 10]},
        'then': [
          // Split: reset to 6 + remainder
          {
            'set': {'+': [6, {'-': [{'var': r'$newPrice'}, 11]}]},
            'path': r'stockPrices.{$company}',
          },
          ..._splitConsequenceEffects(),
          {
            'log': 'MOVEMENT',
            'message': {
              'cat': [
                {'var': r'$company'},
                ' SPLIT → \$',
                {'var': r'stockPrices.{$company}'},
              ],
            },
          },
        ],
        'else': [
          {
            'if': {'<': [{'var': r'$newPrice'}, 1]},
            'then': [
              // Bankruptcy: reset to 5
              {'set': 5, 'path': r'stockPrices.{$company}'},
              ..._bankruptcyConsequenceEffects(),
              {
                'log': 'MOVEMENT',
                'message': {
                  'cat': [{'var': r'$company'}, ' BANKRUPT → \$5'],
                },
              },
            ],
            'else': [
              // Normal price change
              {'set': {'var': r'$newPrice'}, 'path': r'stockPrices.{$company}'},
              {
                'log': 'MOVEMENT',
                'message': {
                  'cat': [
                    {'var': r'$company'},
                    ' ',
                    {
                      'if': [
                        {'>=': [{'var': r'$change'}, 0]},
                        '+',
                        '',
                      ],
                    },
                    {'var': r'$change'},
                    ' → \$',
                    {'var': r'stockPrices.{$company}'},
                  ],
                },
              },
            ],
          },
        ],
      },
    ],
  },
];

/// Movement phase: apply all 6 forecasts for current round.
List<Map<String, dynamic>> _movementEffects() => [
  {
    'let': {
      r'$roundCompanies': {
        'get': [
          {'var': 'forecastCompanies'},
          {'-': [{'var': 'round'}, 1]},
        ],
      },
      r'$roundChanges': {
        'get': [
          {'var': 'forecastChanges'},
          {'-': [{'var': 'round'}, 1]},
        ],
      },
    },
    'do': [
      {
        'forEach': {'range': 6},
        'as': r'$fi',
        'do': [
          {
            'let': {
              r'$company': {
                'get': [{'var': r'$roundCompanies'}, {'var': r'$fi'}],
              },
              r'$change': {
                'get': [{'var': r'$roundChanges'}, {'var': r'$fi'}],
              },
            },
            'do': [
              {
                'if': {'==': [{'var': r'$change'}, _kDividendSentinel]},
                'then': _dividendEffects(),
                'else': _priceChangeEffects(),
              },
            ],
          },
        ],
      },
    ],
  },
];

/// Setup effects for a new round. Assumes 'round' is already set.
List<Map<String, dynamic>> _setupRoundEffects() => [
  // Reset phase tracking
  {'set': {'literal': []}, 'path': 'phaseActedPlayers'},
  {'set': {'literal': {}}, 'path': 'demandBids'},
  {'set': 1, 'path': 'demandRound'},
  {'set': {'literal': []}, 'path': 'outbidPlayers'},
  {'set': {'literal': []}, 'path': 'rebidActedPlayers'},
  {'set': {'literal': []}, 'path': 'demandPassedPlayers'},
  {'setPhase': 'supply'},

  // Create stockpiles (one per player, each with 1 face-up card)
  {'set': {'literal': []}, 'path': 'stockpiles'},
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$_sp',
    'index': r'$spIdx',
    'do': [
      {
        'append': 'stockpiles',
        'value': {
          'literal': {
            'faceUpCards': <dynamic>[],
            'faceDownCards': <dynamic>[],
            'currentBid': 0,
            'currentBidderId': null,
          },
        },
      },
      {
        'if': {'isNotEmpty': {'var': 'marketDeck'}},
        'then': [
          {
            'drawCards': {
              'from': 'marketDeck',
              'to': r'stockpiles.{$spIdx}.faceUpCards',
              'count': 1,
            },
          },
        ],
      },
    ],
  },

  // Deal 2 supply cards to each player
  {'set': {'literal': {}}, 'path': 'supplyHands'},
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$pid',
    'do': [
      {'set': {'literal': []}, 'path': r'supplyHands.{$pid}'},
      {
        'drawCards': {
          'from': 'marketDeck',
          'to': r'supplyHands.{$pid}',
          'count': 2,
        },
      },
    ],
  },

  // Reset supply placed tracking
  {'set': {'literal': {}}, 'path': 'supplyPlaced'},
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$pid',
    'do': [
      {
        'set': {'literal': {'faceUp': false, 'faceDown': false}},
        'path': r'supplyPlaced.{$pid}',
      },
    ],
  },

  // Preserve existing action cards, reset for players who don't have any
  {
    'forEach': {'var': 'playerOrder'},
    'as': r'$pid',
    'do': [
      {
        'if': {
          '==': [
            {'get': [{'var': 'actionCards'}, {'var': r'$pid'}]},
            null,
          ],
        },
        'then': [
          {'set': {'literal': []}, 'path': r'actionCards.{$pid}'},
        ],
      },
    ],
  },

  // Assign forecasts (public + private)
  {
    'let': {
      r'$indices': {'shuffle': {'literal': [0, 1, 2, 3, 4, 5]}},
      r'$roundIdx': {'-': [{'var': 'round'}, 1]},
    },
    'do': [
      {
        'let': {
          r'$publicIdx': {'get': [{'var': r'$indices'}, 0]},
        },
        'do': [
          {
            'set': {
              'get': [
                {'get': [{'var': 'forecastCompanies'}, {'var': r'$roundIdx'}]},
                {'var': r'$publicIdx'},
              ],
            },
            'path': 'publicForecast.company',
          },
          {
            'set': {
              'get': [
                {'get': [{'var': 'forecastChanges'}, {'var': r'$roundIdx'}]},
                {'var': r'$publicIdx'},
              ],
            },
            'path': 'publicForecast.change',
          },
          // Private forecasts
          {'set': {'literal': {}}, 'path': 'privateForecastByPlayer'},
          {
            'forEach': {'var': 'playerOrder'},
            'as': r'$pid',
            'index': r'$pIdx',
            'do': [
              {
                'let': {
                  r'$privateIdx': {
                    'get': [
                      {'var': r'$indices'},
                      {'+': [{'var': r'$pIdx'}, 1]},
                    ],
                  },
                },
                'do': [
                  {
                    'set': {
                      'get': [
                        {
                          'get': [
                            {'var': 'forecastCompanies'},
                            {'var': r'$roundIdx'},
                          ],
                        },
                        {'var': r'$privateIdx'},
                      ],
                    },
                    'path': r'privateForecastByPlayer.{$pid}.company',
                  },
                  {
                    'set': {
                      'get': [
                        {
                          'get': [
                            {'var': 'forecastChanges'},
                            {'var': r'$roundIdx'},
                          ],
                        },
                        {'var': r'$privateIdx'},
                      ],
                    },
                    'path': r'privateForecastByPlayer.{$pid}.change',
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },

  // Set first player active
  {
    'setActivePlayer': {'get': [{'var': 'playerOrder'}, 0]},
  },
  {
    'setTurn': {
      'turnIndex': 0,
      'activePlayerId': {'get': [{'var': 'playerOrder'}, 0]},
      'actionCountThisTurn': 0,
    },
  },
];

/// After movement: next round or game end.
List<Map<String, dynamic>> _postMovementEffects() => [
  {
    'if': {'>=': [{'var': 'round'}, {'var': 'totalRounds'}]},
    'then': [
      // Game over — increment round past total to trigger checkGameEnd
      {'increment': 'round', 'by': 1},
    ],
    'else': [
      // Next round
      {'increment': 'round', 'by': 1},
      ..._setupRoundEffects(),
    ],
  },
];

/// Compute one player's total wealth (expression, expects $pid in scope).
Map<String, dynamic> _computeWealthExpr() => {
  '+': [
    // Cash
    _cashOf(r'$pid'),
    // Normal portfolio value
    {
      'reduce': {
        'list': {'literal': _kCompanies},
        'as': r'$c',
        'acc': r'$total',
        'init': 0,
        'to': {
          '+': [
            {'var': r'$total'},
            {'*': [_portfolioShares(r'$pid', r'$c'), _priceOf(r'$c')]},
          ],
        },
      },
    },
    // Split portfolio value (2× price)
    {
      'reduce': {
        'list': {'literal': _kCompanies},
        'as': r'$c',
        'acc': r'$total',
        'init': 0,
        'to': {
          '+': [
            {'var': r'$total'},
            {
              '*': [
                _splitShares(r'$pid', r'$c'),
                {'*': [2, _priceOf(r'$c')]},
              ],
            },
          ],
        },
      },
    },
    // Majority bonus
    _majorityBonusExpr(),
  ],
};

/// Compute majority bonuses for one player (expects $pid in scope).
Map<String, dynamic> _majorityBonusExpr() => {
  'reduce': {
    'list': {'literal': _kCompanies},
    'as': r'$mc',
    'acc': r'$bonus',
    'init': 0,
    'to': {
      'let': {
        r'$effectiveShares': {
          'map': {
            'list': {'var': 'playerOrder'},
            'as': r'$mp',
            'to': {
              '+': [
                _portfolioShares(r'$mp', r'$mc'),
                {'*': [2, _splitShares(r'$mp', r'$mc')]},
              ],
            },
          },
        },
        r'$maxShares': {
          'reduce': {
            'list': {
              'map': {
                'list': {'var': 'playerOrder'},
                'as': r'$mp',
                'to': {
                  '+': [
                    _portfolioShares(r'$mp', r'$mc'),
                    {'*': [2, _splitShares(r'$mp', r'$mc')]},
                  ],
                },
              },
            },
            'as': r'$s',
            'acc': r'$best',
            'init': 0,
            'to': {'max': [{'var': r'$best'}, {'var': r'$s'}]},
          },
        },
        r'$myShares': {
          '+': [
            _portfolioShares(r'$pid', r'$mc'),
            {'*': [2, _splitShares(r'$pid', r'$mc')]},
          ],
        },
      },
      'in': {
        'if': [
          {
            'and': [
              {'>': [{'var': r'$maxShares'}, 0]},
              {'==': [{'var': r'$myShares'}, {'var': r'$maxShares'}]},
            ],
          },
          {
            '+': [
              {'var': r'$bonus'},
              {
                'let': {
                  r'$leaderCount': {
                    'length': {
                      'filter': {
                        'list': {'var': r'$effectiveShares'},
                        'as': r'$es',
                        'where': {
                          '==': [{'var': r'$es'}, {'var': r'$maxShares'}],
                        },
                      },
                    },
                  },
                },
                'in': {
                  'if': [{'==': [{'var': r'$leaderCount'}, 1]}, 10000, 5000],
                },
              },
            ],
          },
          {'var': r'$bonus'},
        ],
      },
    },
  },
};

// ─── Main definition ────────────────────────────────────────────────────────

Map<String, dynamic> _buildDefinition() => {
  'packId': 'stockpile',
  'minPlayers': 3,
  'maxPlayers': 5,
  'boardOrientation': 'landscape',
  'nodeOrientation': 'landscape',

  // ── Setup ──
  'setup': {
    'initialData': {
      'round': 1,
      'totalRounds': 8,
      'phase': 'supply',
      'stockPrices': {
        'literal': {
          'aauto': 5, 'epic': 5, 'fed': 5,
          'lehm': 5, 'sip': 5, 'tot': 5,
        },
      },
      'marketDeck': {'literal': []},
      'discardPile': {'literal': []},
      'cash': {'literal': {}},
      'portfolios': {'literal': {}},
      'splitPortfolios': {'literal': {}},
      'pendingFees': {'literal': {}},
      'forecastCompanies': {'literal': []},
      'forecastChanges': {'literal': []},
      'publicForecast': {'literal': {}},
      'privateForecastByPlayer': {'literal': {}},
      'stockpiles': {'literal': []},
      'supplyHands': {'literal': {}},
      'supplyPlaced': {'literal': {}},
      'demandBids': {'literal': {}},
      'demandRound': 1,
      'outbidPlayers': {'literal': []},
      'rebidActedPlayers': {'literal': []},
      'demandPassedPlayers': {'literal': []},
      'actionCards': {'literal': {}},
      'phaseActedPlayers': {'literal': []},
    },
    'effects': [
      // Calculate totalRounds based on player count
      {
        'if': {'==': [{'length': {'var': 'playerOrder'}}, 3]},
        'then': [{'set': 8, 'path': 'totalRounds'}],
        'else': [
          {
            'if': {'==': [{'length': {'var': 'playerOrder'}}, 4]},
            'then': [{'set': 6, 'path': 'totalRounds'}],
            'else': [{'set': 4, 'path': 'totalRounds'}],
          },
        ],
      },

      // Build market deck: 60 stock + 8 fee_1000 + 4 fee_2000 + 4 boom + 4 bust
      {
        'forEach': {'literal': _kCompanies},
        'as': r'$c',
        'do': [
          {
            'forEach': {'range': 10},
            'as': r'$_',
            'do': [
              {
                'append': 'marketDeck',
                'value': {'cat': ['stock_', {'var': r'$c'}]},
              },
            ],
          },
        ],
      },
      {
        'forEach': {'range': 8},
        'as': r'$_',
        'do': [{'append': 'marketDeck', 'value': 'fee_1000'}],
      },
      {
        'forEach': {'range': 4},
        'as': r'$_',
        'do': [{'append': 'marketDeck', 'value': 'fee_2000'}],
      },
      {
        'forEach': {'range': 4},
        'as': r'$_',
        'do': [{'append': 'marketDeck', 'value': 'action_boom'}],
      },
      {
        'forEach': {'range': 4},
        'as': r'$_',
        'do': [{'append': 'marketDeck', 'value': 'action_bust'}],
      },
      {'shuffleDeck': 'marketDeck'},

      // Generate forecasts for all rounds
      {
        'forEach': {'range': {'var': 'totalRounds'}},
        'as': r'$r',
        'do': [
          {
            'append': 'forecastCompanies',
            'value': {'shuffle': {'literal': _kCompanies}},
          },
          {
            'append': 'forecastChanges',
            'value': {
              'take': {
                'list': {
                  'shuffle': {
                    'literal': [-3, -2, -1, 0, 1, 2, 3, 4, _kDividendSentinel],
                  },
                },
                'count': 6,
              },
            },
          },
        ],
      },

      // Initialize cash and portfolios
      {
        'forEach': {'var': 'playerOrder'},
        'as': r'$pid',
        'do': [
          {'set': 20000, 'path': r'cash.{$pid}'},
          {'set': {'literal': {}}, 'path': r'portfolios.{$pid}'},
          {'set': {'literal': {}}, 'path': r'splitPortfolios.{$pid}'},
          {'set': {'literal': []}, 'path': r'actionCards.{$pid}'},
          {'set': 0, 'path': r'pendingFees.{$pid}'},
        ],
      },

      // Setup round 1
      ..._setupRoundEffects(),
    ],
    'log': [
      {'eventType': 'system', 'description': 'Stockpile game started'},
    ],
  },

  // ── Phases ──
  'phases': {
    // ── Supply phase ──
    'supply': {
      'activePlayerOnly': true,
      'actions': {
        'PLACE_FACE_UP': {
          'allowedWhen': {
            'not': {'var': r'supplyPlaced.{playerId}.faceUp'},
          },
          'generate': _supplyGenerate(),
          'effects': [
            {
              'let': {
                r'$card': {
                  'get': [
                    {'var': r'supplyHands.{playerId}'},
                    {'var': 'action.cardIndex'},
                  ],
                },
              },
              'do': [
                {
                  'remove': r'supplyHands.{playerId}',
                  'value': {'var': r'$card'},
                },
                {
                  'append': r'stockpiles.{stockpileIndex}.faceUpCards',
                  'value': {'var': r'$card'},
                },
                {
                  'set': true,
                  'path': r'supplyPlaced.{playerId}.faceUp',
                },
                {
                  'log': 'PLACE_FACE_UP',
                  'message': {
                    'cat': [
                      {'var': 'playerId'},
                      ' placed face-up on pile ',
                      {'+': [{'var': 'action.stockpileIndex'}, 1]},
                    ],
                  },
                },
                ..._supplyCheckAdvanceEffects(),
              ],
            },
          ],
        },
        'PLACE_FACE_DOWN': {
          'allowedWhen': {
            'not': {'var': r'supplyPlaced.{playerId}.faceDown'},
          },
          'generate': _supplyGenerate(),
          'effects': [
            {
              'let': {
                r'$card': {
                  'get': [
                    {'var': r'supplyHands.{playerId}'},
                    {'var': 'action.cardIndex'},
                  ],
                },
              },
              'do': [
                {
                  'remove': r'supplyHands.{playerId}',
                  'value': {'var': r'$card'},
                },
                {
                  'append': r'stockpiles.{stockpileIndex}.faceDownCards',
                  'value': {'var': r'$card'},
                },
                {
                  'set': true,
                  'path': r'supplyPlaced.{playerId}.faceDown',
                },
                {
                  'log': 'PLACE_FACE_DOWN',
                  'message': {
                    'cat': [
                      {'var': 'playerId'},
                      ' placed face-down on pile ',
                      {'+': [{'var': 'action.stockpileIndex'}, 1]},
                    ],
                  },
                },
                ..._supplyCheckAdvanceEffects(),
              ],
            },
          ],
        },
      },
    },

    // ── Demand phase ──
    'demand': {
      'activePlayerOnly': true,
      'actions': {
        'BID': {
          'generate': {
            'forEach': {
              'filter': {
                'list': {'range': {'length': {'var': 'stockpiles'}}},
                'as': r'$si',
                'where': {
                  'and': [
                    // Not our own pile in rebid round
                    {
                      'or': [
                        {'==': [{'var': 'demandRound'}, 1]},
                        {
                          '!=': [
                            {
                              'get': [
                                {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                                'currentBidderId',
                              ],
                            },
                            {'var': 'playerId'},
                          ],
                        },
                      ],
                    },
                    // Min valid bid <= cash and <= maxBid
                    {
                      'let': {
                        r'$hasBidder': {
                          '!=': [
                            {
                              'get': [
                                {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                                'currentBidderId',
                              ],
                            },
                            null,
                          ],
                        },
                        r'$curBid': {
                          'if': [
                            {
                              'get': [
                                {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                                'currentBidderId',
                              ],
                            },
                            {
                              'get': [
                                {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                                'currentBid',
                              ],
                            },
                            0,
                          ],
                        },
                      },
                      'in': {
                        'let': {
                          r'$minBid': {
                            'if': [
                              {'var': r'$hasBidder'},
                              {'+': [{'var': r'$curBid'}, 1]},
                              0,
                            ],
                          },
                        },
                        'in': {
                          'and': [
                            {'<=': [{'var': r'$minBid'}, _kMaxBid]},
                            {
                              '<=': [
                                {'var': r'$minBid'},
                                {'var': r'cash.{playerId}'},
                              ],
                            },
                          ],
                        },
                      },
                    },
                  ],
                },
              },
            },
            'as': r'$si',
            'label': {
              'cat': [
                'Bid on pile ',
                {'+': [{'var': r'$si'}, 1]},
              ],
            },
            'params': {
              'stockpileIndex': {'var': r'$si'},
              'amount': {
                'let': {
                  r'$hasBidder': {
                    '!=': [
                      {
                        'get': [
                          {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                          'currentBidderId',
                        ],
                      },
                      null,
                    ],
                  },
                  r'$curBid': {
                    'if': [
                      {
                        'get': [
                          {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                          'currentBidderId',
                        ],
                      },
                      {
                        'get': [
                          {'get': [{'var': 'stockpiles'}, {'var': r'$si'}]},
                          'currentBid',
                        ],
                      },
                      0,
                    ],
                  },
                },
                'in': {
                  'if': [
                    {'var': r'$hasBidder'},
                    {'+': [{'var': r'$curBid'}, 1]},
                    0,
                  ],
                },
              },
            },
          },
          'effects': [
            // Track displaced bidder
            {
              'let': {
                r'$prevBidder': {
                  'var': r'stockpiles.{stockpileIndex}.currentBidderId',
                },
              },
              'do': [
                {
                  'if': {
                    'and': [
                      {'!=': [{'var': r'$prevBidder'}, null]},
                      {'!=': [{'var': r'$prevBidder'}, {'var': 'playerId'}]},
                    ],
                  },
                  'then': [
                    {
                      'if': {
                        'not': {
                          'contains': [
                            {'var': 'outbidPlayers'},
                            {'var': r'$prevBidder'},
                          ],
                        },
                      },
                      'then': [
                        {
                          'append': 'outbidPlayers',
                          'value': {'var': r'$prevBidder'},
                        },
                      ],
                    },
                  ],
                },
              ],
            },
            // Remove current player from outbidPlayers
            {'remove': 'outbidPlayers', 'value': {'var': 'playerId'}},
            // Update stockpile
            {
              'set': {'var': 'action.amount'},
              'path': r'stockpiles.{stockpileIndex}.currentBid',
            },
            {
              'set': {'var': 'playerId'},
              'path': r'stockpiles.{stockpileIndex}.currentBidderId',
            },
            // Record bid
            {
              'set': {'var': 'action.stockpileIndex'},
              'path': r'demandBids.{playerId}.stockpileIndex',
            },
            {
              'set': {'var': 'action.amount'},
              'path': r'demandBids.{playerId}.amount',
            },
            {
              'log': 'BID',
              'message': {
                'cat': [
                  {'var': 'playerId'},
                  ' bid \$',
                  {'var': 'action.amount'},
                  ' on pile ',
                  {'+': [{'var': 'action.stockpileIndex'}, 1]},
                ],
              },
            },
            // Advance
            ..._demandAdvanceEffects(),
          ],
        },
        'DEMAND_PASS': {
          'allowedWhen': {'>': [{'var': 'demandRound'}, 1]},
          'label': 'Pass rebid',
          'effects': [
            {
              'if': {
                'not': {
                  'contains': [
                    {'var': 'demandPassedPlayers'},
                    {'var': 'playerId'},
                  ],
                },
              },
              'then': [
                {
                  'append': 'demandPassedPlayers',
                  'value': {'var': 'playerId'},
                },
              ],
            },
            {
              'log': 'DEMAND_PASS',
              'message': {'cat': [{'var': 'playerId'}, ' passed rebid']},
            },
            ..._demandAdvanceEffects(),
          ],
        },
      },
    },

    // ── Action phase ──
    'action': {
      'activePlayerOnly': true,
      'actions': {
        'USE_BOOM': {
          'generate': {
            'forEach': {
              'let': {
                r'$myCards': {
                  'if': [
                    {'get': [{'var': 'actionCards'}, {'var': 'playerId'}]},
                    {'get': [{'var': 'actionCards'}, {'var': 'playerId'}]},
                    {'literal': []},
                  ],
                },
              },
              'in': {
                'if': [
                  {'contains': [{'var': r'$myCards'}, 'action_boom']},
                  {'literal': _kCompanies},
                  {'literal': []},
                ],
              },
            },
            'as': r'$company',
            'label': {
              'cat': ['Boom! ', {'var': r'$company'}, ' (+2)'],
            },
            'params': {
              'company': {'var': r'$company'},
            },
          },
          'effects': [
            // Remove boom card
            {'remove': r'actionCards.{playerId}', 'value': 'action_boom'},
            // Apply +2 price change (with split mechanics)
            {
              'let': {
                r'$company': {'var': 'action.company'},
                r'$change': 2,
              },
              'do': _priceChangeEffects(),
            },
          ],
        },
        'USE_BUST': {
          'generate': {
            'forEach': {
              'let': {
                r'$myCards': {
                  'if': [
                    {'get': [{'var': 'actionCards'}, {'var': 'playerId'}]},
                    {'get': [{'var': 'actionCards'}, {'var': 'playerId'}]},
                    {'literal': []},
                  ],
                },
              },
              'in': {
                'if': [
                  {'contains': [{'var': r'$myCards'}, 'action_bust']},
                  {'literal': _kCompanies},
                  {'literal': []},
                ],
              },
            },
            'as': r'$company',
            'label': {
              'cat': ['Bust! ', {'var': r'$company'}, ' (-2)'],
            },
            'params': {
              'company': {'var': r'$company'},
            },
          },
          'effects': [
            // Remove bust card
            {'remove': r'actionCards.{playerId}', 'value': 'action_bust'},
            // Apply -2 price change (with bankruptcy mechanics)
            {
              'let': {
                r'$company': {'var': 'action.company'},
                r'$change': -2,
              },
              'do': _priceChangeEffects(),
            },
          ],
        },
        'END_PHASE': {
          'label': 'Done with actions',
          'effects': [
            {
              'log': 'END_PHASE',
              'message': {'cat': [{'var': 'playerId'}, ' done with actions']},
            },
            ..._advanceOrTransition(_transitionToPhase('selling')),
          ],
        },
      },
    },

    // ── Selling phase ──
    'selling': {
      'activePlayerOnly': true,
      'actions': {
        'SELL_STOCK': {
          'generate': {
            'forEach': {
              'flatten': {
                'map': {
                  'list': {'literal': _kCompanies},
                  'as': r'$c',
                  'to': {
                    'let': {
                      r'$normal': _portfolioShares('playerId', r'$c'),
                      r'$split': _splitShares('playerId', r'$c'),
                      r'$price': _priceOf(r'$c'),
                    },
                    'in': {
                      'flatten': [
                        {
                          'if': [
                            {'>': [{'var': r'$normal'}, 0]},
                            [
                              {
                                'literal': {
                                  'type': 'normal',
                                  'company': null,
                                  'price': null,
                                },
                              },
                            ],
                            {'literal': []},
                          ],
                        },
                        {
                          'if': [
                            {'>': [{'var': r'$split'}, 0]},
                            [
                              {
                                'literal': {
                                  'type': 'split',
                                  'company': null,
                                  'price': null,
                                },
                              },
                            ],
                            {'literal': []},
                          ],
                        },
                      ],
                    },
                  },
                },
              },
            },
            'as': r'$opt',
            'label': {'cat': ['Sell stock']},
            'params': {
              'company': {'var': r'$opt'},
              'type': 'normal',
            },
          },
          // Simplified: generate per company with shares
          'effects': [
            {
              'let': {
                r'$company': {'var': 'action.company'},
                r'$type': {'var': 'action.type'},
                r'$price': {
                  'if': [
                    {'var': r'stockPrices.{action.company}'},
                    {'var': r'stockPrices.{action.company}'},
                    0,
                  ],
                },
              },
              'do': [
                {
                  'if': {'==': [{'var': r'$type'}, 'normal']},
                  'then': [
                    {
                      'increment': r'portfolios.{playerId}.{$company}',
                      'by': -1,
                    },
                    {
                      'increment': r'cash.{playerId}',
                      'by': {'var': r'$price'},
                    },
                    {
                      'log': 'SELL_STOCK',
                      'message': {
                        'cat': [
                          {'var': 'playerId'},
                          ' sold ',
                          {'var': r'$company'},
                          ' normal @ \$',
                          {'var': r'$price'},
                        ],
                      },
                    },
                  ],
                  'else': [
                    {
                      'increment': r'splitPortfolios.{playerId}.{$company}',
                      'by': -1,
                    },
                    {
                      'increment': r'cash.{playerId}',
                      'by': {'*': [{'var': r'$price'}, 2]},
                    },
                    {
                      'log': 'SELL_STOCK',
                      'message': {
                        'cat': [
                          {'var': 'playerId'},
                          ' sold ',
                          {'var': r'$company'},
                          ' split @ \$',
                          {'*': [{'var': r'$price'}, 2]},
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          ],
        },
        'END_PHASE': {
          'label': 'Done selling',
          'effects': [
            {
              'log': 'END_PHASE',
              'message': {'cat': [{'var': 'playerId'}, ' done selling']},
            },
            ..._advanceOrTransition([
              // All done selling → movement phase (automatic)
              ..._movementEffects(),
              ..._postMovementEffects(),
            ]),
          ],
        },
      },
    },
  },

  // ── Game end ──
  'gameEnd': {
    'condition': {'>': [{'var': 'round'}, {'var': 'totalRounds'}]},
    'winners': {
      'let': {
        r'$wealthList': {
          'map': {
            'list': {'var': 'playerOrder'},
            'as': r'$pid',
            'to': _computeWealthExpr(),
          },
        },
        r'$maxW': {
          'reduce': {
            'list': {
              'map': {
                'list': {'var': 'playerOrder'},
                'as': r'$pid',
                'to': _computeWealthExpr(),
              },
            },
            'as': r'$w',
            'acc': r'$best',
            'init': 0,
            'to': {'max': [{'var': r'$best'}, {'var': r'$w'}]},
          },
        },
      },
      'in': {
        'map': {
          'list': {
            'filter': {
              'list': {
                'range': {'length': {'var': 'playerOrder'}},
              },
              'as': r'$i',
              'where': {
                '==': [
                  {'get': [{'var': r'$wealthList'}, {'var': r'$i'}]},
                  {'var': r'$maxW'},
                ],
              },
            },
          },
          'as': r'$i',
          'to': {'get': [{'var': 'playerOrder'}, {'var': r'$i'}]},
        },
      },
    },
  },

  // ── Board view ──
  'boardView': {
    'data': {
      'packId': 'stockpile',
      'phase': {'var': 'phase'},
      'round': {'var': 'round'},
      'totalRounds': {'var': 'totalRounds'},
      'stockPrices': {'var': 'stockPrices'},
      'cash': {'var': 'cash'},
      'publicForecast': {'var': 'publicForecast'},
      'stockpiles': {
        'map': {
          'list': {'var': 'stockpiles'},
          'as': r'$sp',
          'to': {
            'literal': {},
          },
        },
      },
    },
    'maxRecentLog': 10,
  },

  // ── Player view ──
  'playerView': {
    'data': {
      'packId': 'stockpile',
      'phase': {'var': 'phase'},
      'round': {'var': 'round'},
      'totalRounds': {'var': 'totalRounds'},
      'portfolio': {
        'if': [
          {'get': [{'var': 'portfolios'}, {'var': 'playerId'}]},
          {'get': [{'var': 'portfolios'}, {'var': 'playerId'}]},
          {'literal': {}},
        ],
      },
      'splitPortfolio': {
        'if': [
          {'get': [{'var': 'splitPortfolios'}, {'var': 'playerId'}]},
          {'get': [{'var': 'splitPortfolios'}, {'var': 'playerId'}]},
          {'literal': {}},
        ],
      },
      'privateForecast': {
        'get': [{'var': 'privateForecastByPlayer'}, {'var': 'playerId'}],
      },
      'actionCards': {
        'if': [
          {'get': [{'var': 'actionCards'}, {'var': 'playerId'}]},
          {'get': [{'var': 'actionCards'}, {'var': 'playerId'}]},
          {'literal': []},
        ],
      },
      'pendingFees': {
        'if': [
          {'get': [{'var': 'pendingFees'}, {'var': 'playerId'}]},
          {'get': [{'var': 'pendingFees'}, {'var': 'playerId'}]},
          0,
        ],
      },
      'myBid': {'get': [{'var': 'demandBids'}, {'var': 'playerId'}]},
      'supplyPlaced': {
        'if': [
          {'get': [{'var': 'supplyPlaced'}, {'var': 'playerId'}]},
          {'get': [{'var': 'supplyPlaced'}, {'var': 'playerId'}]},
          {'literal': {'faceUp': false, 'faceDown': false}},
        ],
      },
      'demandRound': {'var': 'demandRound'},
      'outbidPlayers': {'var': 'outbidPlayers'},
    },
    'hand': {'var': r'supplyHands.{playerId}'},
    'scores': {'var': 'cash'},
  },
};
