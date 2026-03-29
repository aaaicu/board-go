import 'dart:math';

import '../../game_session/game_log_entry.dart';
import '../../game_session/game_session_state.dart';
import '../../game_session/session_phase.dart';
import '../../game_session/turn_state.dart';
import '../../game_session/turn_step.dart';
import '../../messages/node_message.dart';
import '../game_state.dart';
import '../player_action.dart';
import '../views/allowed_action.dart';
import '../views/board_view.dart';
import '../views/player_view.dart';
import '../game_pack_rules.dart';

class SecretHitlerRules implements GamePackRules {
  @override
  String get packId => 'secret_hitler';

  @override
  int get minPlayers => 5;

  @override
  int get maxPlayers => 10;

  @override
  String get boardOrientation => 'landscape';

  @override
  String get nodeOrientation => 'portrait';

  @override
  GameSessionState createInitialGameState(GameSessionState sessionState) {
    final playerOrder = List<String>.from(sessionState.players.keys)..shuffle();
    final playerCount = playerOrder.length;
    
    int fascistCount = 0;
    if (playerCount == 5 || playerCount == 6) {
      fascistCount = 1;
    } else if (playerCount == 7 || playerCount == 8) {
      fascistCount = 2;
    } else {
      fascistCount = 3;
    }

    int liberalCount = playerCount - (fascistCount + 1);
    
    final rolePool = <String>['HITLER'];
    for (int i = 0; i < fascistCount; i++) {
       rolePool.add('FASCIST');
    }
    for (int i = 0; i < liberalCount; i++) {
       rolePool.add('LIBERAL');
    }
    rolePool.shuffle(Random());

    final roles = <String, String>{};
    for (int i = 0; i < playerCount; i++) {
        roles[playerOrder[i]] = rolePool[i];
    }

    final deck = <String>[];
    for (int i = 0; i < 11; i++) {
       deck.add('FASCIST');
    }
    for (int i = 0; i < 6; i++) {
       deck.add('LIBERAL');
    }
    deck.shuffle(Random());

    final initialData = {
      'phase': 'ROLE_REVEAL',
      'roles': roles,
      'readyPlayers': <String>[],
      'deck': deck,
      'discard': <String>[],
      'liberalPolicies': 0,
      'fascistPolicies': 0,
      'electionTracker': 0,
      'presidentPosition': 0, 
      'presidentId': playerOrder[0],
      'chancellorCandidateId': null,
      'chancellorId': null,
      'previousPresidentId': null,
      'previousChancellorId': null,
      'votes': <String, String>{},
      'drawnPolicies': <String>[],
      'executiveActionType': 'NONE',
      'vetoUnlocked': false,
      'deadPlayers': <String>[],
      'investigatedPlayers': <String>[],
      'specialElectionReturnIndex': null,
      'winner': null,
    };

    final turnState = TurnState(
      round: 1,
      turnIndex: 0,
      activePlayerId: playerOrder[0],
      step: TurnStep.start,
      actionCountThisTurn: 0,
    );

    final gameState = GameState(
      gameId: sessionState.sessionId,
      turn: 1,
      activePlayerId: playerOrder[0],
      data: initialData,
    );

    return sessionState.copyWith(
      phase: SessionPhase.inGame,
      turnState: turnState,
      gameState: gameState,
      playerOrder: playerOrder,
    ).addLog(GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'system',
      description: '시크릿 히틀러 게임이 시작되었습니다! 각자의 역할을 확인하세요.',
    ));
  }

  @override
  List<AllowedAction> getAllowedActions(GameSessionState state, String playerId) {
    if (state.gameState == null) return [];
    final data = state.gameState!.data;
    final phase = data['phase'] as String;
    
    final deadPlayers = List<String>.from(data['deadPlayers'] ?? []);
    if (deadPlayers.contains(playerId)) return [];
    if (data['winner'] != null) return [];

    final actions = <AllowedAction>[];
    
    if (phase == 'ROLE_REVEAL') {
      final ready = List<String>.from(data['readyPlayers'] ?? []);
      if (!ready.contains(playerId)) {
        actions.add(const AllowedAction(
          actionType: 'READY',
          label: '역할 확인 완료',
          params: {},
        ));
      }
    } else if (phase == 'CHANCELLOR_NOMINATION') {
      if (data['presidentId'] == playerId) {
        actions.add(const AllowedAction(
          actionType: 'NOMINATE',
          label: '수상 후보 지명',
          params: {},
        ));
      }
    } else if (phase == 'VOTING') {
      final votes = data['votes'] as Map<String, dynamic>? ?? {};
      if (!votes.containsKey(playerId)) {
        actions.add(const AllowedAction(
          actionType: 'VOTE_JA',
          label: 'Ja (찬성)',
          params: {},
        ));
        actions.add(const AllowedAction(
          actionType: 'VOTE_NEIN',
          label: 'Nein (반대)',
          params: {},
        ));
      }
    } else if (phase == 'LEGISLATIVE_PRESIDENT') {
      if (data['presidentId'] == playerId) {
        actions.add(const AllowedAction(
          actionType: 'DISCARD_POLICY',
          label: '정책 1장 버리기',
          params: {},
        ));
      }
    } else if (phase == 'LEGISLATIVE_CHANCELLOR') {
      if (data['chancellorId'] == playerId) {
        actions.add(const AllowedAction(
          actionType: 'ENACT_POLICY',
          label: '이 정책 제정하기',
          params: {},
        ));
        if (data['vetoUnlocked'] == true && data['vetoRequested'] != true) {
          actions.add(const AllowedAction(
            actionType: 'REQUEST_VETO',
            label: '거부권 요청',
            params: {},
          ));
        }
      }
    } else if (phase == 'VETO_RESPONSE') {
      if (data['presidentId'] == playerId) {
        actions.add(const AllowedAction(
          actionType: 'VETO_APPROVE',
          label: '거부권 찬성 (폐기)',
          params: {},
        ));
        actions.add(const AllowedAction(
          actionType: 'VETO_REJECT',
          label: '거부권 반대 (강제 제정)',
          params: {},
        ));
      }
    } else if (phase == 'EXECUTIVE_ACTION') {
      if (data['presidentId'] == playerId) {
        final actionType = data['executiveActionType'] as String;
        if (actionType == 'INVESTIGATE') {
          actions.add(const AllowedAction(
            actionType: 'EXEC_INVESTIGATE',
            label: '플레이어 조사',
            params: {},
          ));
        } else if (actionType == 'SPECIAL_ELECTION') {
          actions.add(const AllowedAction(
            actionType: 'EXEC_SPECIAL_ELECTION',
            label: '특별 선거 지정',
            params: {},
          ));
        } else if (actionType == 'EXECUTION') {
          actions.add(const AllowedAction(
            actionType: 'EXEC_EXECUTION',
            label: '플레이어 처형',
            params: {},
          ));
        } else if (actionType == 'POLICY_PEEK') {
          actions.add(const AllowedAction(
            actionType: 'EXEC_FINISH_PEEK',
            label: '엿보기 완료',
            params: {},
          ));
        }
      }
    }

    return actions;
  }

  @override
  GameSessionState applyAction(GameSessionState state, String playerId, PlayerAction action) {
    var data = Map<String, dynamic>.from(state.gameState!.data);
    var logs = List<GameLogEntry>.from(state.log);
    
    void addLog(String message) {
      logs.add(GameLogEntry(timestamp: DateTime.now().millisecondsSinceEpoch, eventType: 'system', description: message));
    }

    if (action.type == 'READY') {
      final ready = List<String>.from(data['readyPlayers'] ?? []);
      if (!ready.contains(playerId)) {
         ready.add(playerId);
      }
      data['readyPlayers'] = ready;
      if (ready.length == state.playerOrder.length) {
        data['phase'] = 'CHANCELLOR_NOMINATION';
        addLog('모두가 역할을 확인했습니다. 선거를 시작합니다.');
      }
    } else if (action.type == 'NOMINATE') {
      final target = action.data['targetId'] as String;
      data['chancellorCandidateId'] = target;
      data['phase'] = 'VOTING';
      data['votes'] = <String, String>{};
      addLog('대통령이 $target을(를) 수상 후보로 지명했습니다. 투표를 진행하세요.');
    } else if (action.type == 'VOTE_JA' || action.type == 'VOTE_NEIN') {
      final votes = Map<String, String>.from(data['votes'] ?? {});
      votes[playerId] = action.type == 'VOTE_JA' ? 'JA' : 'NEIN';
      data['votes'] = votes;
      
      final deadPlayers = List<String>.from(data['deadPlayers'] ?? []);
      int aliveCount = state.playerOrder.length - deadPlayers.length;
      if (votes.length == aliveCount) {
        int jas = votes.values.where((v) => v == 'JA').length;
        if (jas > aliveCount / 2) {
          data['chancellorId'] = data['chancellorCandidateId'];
          data['electionTracker'] = 0;
          addLog('투표가 과반수 찬성으로 가결되었습니다. 새 정부가 수립되었습니다.');
          
          final roles = data['roles'] as Map<String, dynamic>;
          final chancellorRole = roles[data['chancellorId']];
          int fascistPolicies = data['fascistPolicies'] as int;
          if (fascistPolicies >= 3 && chancellorRole == 'HITLER') {
            data['winner'] = 'FASCIST';
            addLog('히틀러가 수상으로 선출되었습니다! 파시스트 승리!');
          } else {
            var deck = List<String>.from(data['deck']);
            var discard = List<String>.from(data['discard']);
            if (deck.length < 3) {
              deck.addAll(discard);
              deck.shuffle(Random());
              discard.clear();
              addLog('덱을 셔플했습니다.');
            }
            final drawn = deck.take(3).toList();
            deck.removeRange(0, 3);
            data['deck'] = deck;
            data['discard'] = discard;
            data['drawnPolicies'] = drawn;
            data['phase'] = 'LEGISLATIVE_PRESIDENT';
          }
        } else {
          addLog('투표가 부결되었습니다.');
          int tracker = (data['electionTracker'] as int) + 1;
          if (tracker >= 3) {
            addLog('선거가 3번 연속 실패하여, 혼란에 빠졌습니다! 덱의 맨 위 정책이 강제로 제정됩니다.');
            tracker = 0;
            var deck = List<String>.from(data['deck']);
            var discard = List<String>.from(data['discard']);
            if (deck.isEmpty) {
               deck.addAll(discard);
               deck.shuffle(Random());
               discard.clear();
            }
            final enacted = deck.removeAt(0);
            data['deck'] = deck;
            data['discard'] = discard;
            data['previousPresidentId'] = null;
            data['previousChancellorId'] = null;
            if (enacted == 'LIBERAL') {
              data['liberalPolicies'] = (data['liberalPolicies'] as int) + 1;
              addLog('강제 제정: 진보 정책 제정!');
            } else {
              data['fascistPolicies'] = (data['fascistPolicies'] as int) + 1;
              addLog('강제 제정: 파시스트 정책 제정!');
            }
            _checkWinOrNextRound(state, data, addLog);
          } else {
            data['electionTracker'] = tracker;
            _nextPresident(state, data);
            data['phase'] = 'CHANCELLOR_NOMINATION';
          }
        }
      }
    } else if (action.type == 'DISCARD_POLICY') {
      final index = action.data['discardIndex'] as int;
      final drawn = List<String>.from(data['drawnPolicies']);
      final discardList = List<String>.from(data['discard']);
      discardList.add(drawn.removeAt(index));
      data['discard'] = discardList;
      data['drawnPolicies'] = drawn; 
      data['phase'] = 'LEGISLATIVE_CHANCELLOR';
      addLog('대통령이 정책 1장을 버리고 수상에게 2장을 넘겼습니다.');
    } else if (action.type == 'ENACT_POLICY') {
      final enactIndex = action.data['enactIndex'] as int;
      final drawn = List<String>.from(data['drawnPolicies']);
      final discardList = List<String>.from(data['discard']);
      final enacted = drawn.removeAt(enactIndex);
      discardList.add(drawn[0]);
      data['discard'] = discardList;
      data['drawnPolicies'] = <String>[];
      
      data['previousPresidentId'] = data['presidentId'];
      data['previousChancellorId'] = data['chancellorId'];

      if (enacted == 'LIBERAL') {
        data['liberalPolicies'] = (data['liberalPolicies'] as int) + 1;
        addLog('자유주의(Liberal) 정책이 제정되었습니다!');
        _checkWinOrNextRound(state, data, addLog);
      } else {
        int fascists = (data['fascistPolicies'] as int) + 1;
        data['fascistPolicies'] = fascists;
        addLog('파시스트(Fascist) 정책이 제정되었습니다!');
        if (fascists == 5) {
          data['vetoUnlocked'] = true;
        }
        
        if (fascists >= 6) {
           data['winner'] = 'FASCIST';
           addLog('파시스트 정책이 6장 제정되었습니다. 파시스트 승리!');
        } else {
           final playerCount = state.playerOrder.length;
           String exec = 'NONE';
           if (fascists == 1 && playerCount >= 9) exec = 'INVESTIGATE';
           if (fascists == 2 && playerCount >= 7) exec = 'INVESTIGATE';
           if (fascists == 3 && playerCount >= 7) exec = 'SPECIAL_ELECTION';
           if (fascists == 3 && playerCount <= 6) exec = 'POLICY_PEEK';
           if (fascists >= 4) exec = 'EXECUTION';
           
           if (exec == 'NONE') {
             _nextPresident(state, data);
             data['phase'] = 'CHANCELLOR_NOMINATION';
           } else {
             data['executiveActionType'] = exec;
             data['phase'] = 'EXECUTIVE_ACTION';
             addLog('대통령 임원 권한 발동: $exec');
             if (exec == 'POLICY_PEEK') {
                var deck = List<String>.from(data['deck']);
                var discard = List<String>.from(data['discard']);
                if (deck.length < 3) {
                  deck.addAll(discard);
                  deck.shuffle(Random());
                  discard.clear();
                }
                data['deck'] = deck;
                data['discard'] = discard;
             }
           }
        }
      }
    } else if (action.type == 'REQUEST_VETO') {
      data['vetoRequested'] = true;
      data['phase'] = 'VETO_RESPONSE';
      addLog('수상이 거부권(Veto)을 요청했습니다.');
    } else if (action.type == 'VETO_APPROVE') {
      data['vetoRequested'] = false;
      var discardList = List<String>.from(data['discard']);
      discardList.addAll(List<String>.from(data['drawnPolicies']));
      data['discard'] = discardList;
      data['drawnPolicies'] = <String>[];
      addLog('대통령이 거부권에 동의했습니다. 모든 카드를 버립니다.');
      int tracker = (data['electionTracker'] as int) + 1;
      data['electionTracker'] = tracker;
      if (tracker >= 3) {
         addLog('거부권으로 인해 선거 트래커가 3이 되었습니다! 위기 모드로 전환.');
      }
      _nextPresident(state, data);
      data['phase'] = 'CHANCELLOR_NOMINATION';
    } else if (action.type == 'VETO_REJECT') {
      data['vetoRequested'] = false;
      data['phase'] = 'LEGISLATIVE_CHANCELLOR';
      addLog('대통령이 거부권을 거절했습니다! 수상은 반드시 제정해야 합니다.');
    } else if (action.type == 'EXEC_EXECUTION') {
      final target = action.data['targetId'] as String;
      final dead = List<String>.from(data['deadPlayers'] ?? []);
      dead.add(target);
      data['deadPlayers'] = dead;
      addLog('대통령이 $target을(를) 처형했습니다!');
      
      final roles = data['roles'] as Map<String, dynamic>;
      final role = roles[target];
      if (role == 'HITLER') {
         data['winner'] = 'LIBERAL';
         addLog('히틀러가 사망했습니다! 자유주의 승리!');
      } else {
         _nextPresident(state, data);
         data['phase'] = 'CHANCELLOR_NOMINATION';
      }
    } else if (action.type == 'EXEC_INVESTIGATE') {
      final target = action.data['targetId'] as String;
      final investigated = List<String>.from(data['investigatedPlayers'] ?? []);
      investigated.add(target);
      data['investigatedPlayers'] = investigated;
      addLog('대통령이 $target의 당적을 조사했습니다.');
      _nextPresident(state, data);
      data['phase'] = 'CHANCELLOR_NOMINATION';
    } else if (action.type == 'EXEC_SPECIAL_ELECTION') {
       final target = action.data['targetId'] as String;
       data['specialElectionReturnIndex'] = data['presidentPosition'];
       data['presidentId'] = target;
       data['presidentPosition'] = state.playerOrder.indexOf(target);
       addLog('대통령이 다음 특별 대통령으로 $target을 지목했습니다.');
       data['phase'] = 'CHANCELLOR_NOMINATION';
    } else if (action.type == 'EXEC_FINISH_PEEK') {
       addLog('대통령이 덱 상단 3장을 엿보았습니다.');
       _nextPresident(state, data);
       data['phase'] = 'CHANCELLOR_NOMINATION';
    }

    var trimmedLog = logs;
    if (trimmedLog.length > 50) {
      trimmedLog = trimmedLog.sublist(trimmedLog.length - 50);
    }

    return state.copyWith(
      gameState: state.gameState!.copyWith(data: data),
      log: trimmedLog,
      version: state.version + 1,
    );
  }

  void _checkWinOrNextRound(GameSessionState state, Map<String, dynamic> data, Function(String) addLog) {
     if ((data['liberalPolicies'] as int) == 5) {
        data['winner'] = 'LIBERAL';
        addLog('자유주의 정책이 5장 제정되었습니다! 자유주의 승리!');
     } else {
        _nextPresident(state, data);
        data['phase'] = 'CHANCELLOR_NOMINATION';
     }
  }

  void _nextPresident(GameSessionState state, Map<String, dynamic> data) {
      final dead = List<String>.from(data['deadPlayers'] ?? []);
      int pos = 0;
      if (data['specialElectionReturnIndex'] != null) {
          pos = data['specialElectionReturnIndex'] as int;
          data['specialElectionReturnIndex'] = null;
      } else {
          pos = data['presidentPosition'] as int;
      }
      
      do {
         pos = (pos + 1) % state.playerOrder.length;
      } while(dead.contains(state.playerOrder[pos]));

      data['presidentPosition'] = pos;
      data['presidentId'] = state.playerOrder[pos];
      data['chancellorId'] = null;
      data['chancellorCandidateId'] = null;
  }

  @override
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state) {
    if (state.gameState == null) return (ended: false, winnerIds: const []);
    final winner = state.gameState!.data['winner'] as String?;
    if (winner != null) {
      return (ended: true, winnerIds: const []);
    }
    return (ended: false, winnerIds: const []);
  }

  @override
  BoardView buildBoardView(GameSessionState state) {
    final safeData = Map<String, dynamic>.from(state.gameState?.data ?? {});
    final deckList = List<String>.from(safeData['deck'] ?? []);
    final discardList = List<String>.from(safeData['discard'] ?? []);

    safeData.remove('deck');
    safeData.remove('drawnPolicies');
    safeData.remove('roles');
    safeData['packId'] = 'secret_hitler';

    return BoardView(
      phase: state.phase,
      scores: const {},
      turnState: state.turnState,
      deckRemaining: deckList.length,
      discardPile: discardList,
      recentLog: state.log,
      version: state.version,
      data: safeData,
    );
  }

  @override
  PlayerView buildPlayerView(GameSessionState state, String playerId) {
    if (state.gameState == null) {
        return PlayerView(
          phase: state.phase,
          playerId: playerId,
          hand: const [],
          scores: const {},
          turnState: state.turnState,
          allowedActions: const [],
          version: state.version,
        );
    }
    
    final data = state.gameState!.data;
    final privateInfo = <String, dynamic>{
        'packId': 'secret_hitler',
    };
    
    final roles = data['roles'] as Map<String, dynamic>;
    final myRole = roles[playerId];
    privateInfo['myRole'] = myRole;
    privateInfo['myParty'] = (myRole == 'HITLER' || myRole == 'FASCIST') ? 'FASCIST' : 'LIBERAL';
    
    int playerCount = state.playerOrder.length;
    if (myRole == 'FASCIST' || (myRole == 'HITLER' && playerCount <= 6)) {
        final allies = <String>[];
        String hitlerId = '';
        roles.forEach((k, v) {
           if (v == 'FASCIST') allies.add(k);
           if (v == 'HITLER') hitlerId = k as String;
        });
        privateInfo['fascistAllies'] = allies;
        privateInfo['hitlerId'] = hitlerId;
    }

    final phase = data['phase'];
    if (data['presidentId'] == playerId) {
       if (phase == 'LEGISLATIVE_PRESIDENT' || (phase == 'EXECUTIVE_ACTION' && data['executiveActionType'] == 'POLICY_PEEK')) {
           privateInfo['drawnPolicies'] = data['drawnPolicies'];
           if (phase == 'EXECUTIVE_ACTION' && (data['drawnPolicies'] as List).isEmpty) {
              final deck = data['deck'] as List;
              privateInfo['drawnPolicies'] = deck.take(3).toList();
           }
       }
    }
    if (data['chancellorId'] == playerId && phase == 'LEGISLATIVE_CHANCELLOR') {
       privateInfo['drawnPolicies'] = data['drawnPolicies'];
    }

    return PlayerView(
      phase: state.phase,
      playerId: playerId,
      hand: const [],
      scores: const {},
      turnState: state.turnState,
      allowedActions: getAllowedActions(state, playerId),
      version: state.version,
      data: privateInfo,
    );
  }

  @override
  NodeMessage? onNodeMessage(NodeMessage msg, GameSessionState state) {
    return msg;
  }
}
