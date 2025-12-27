# Vyapari Phase-Based Checklist Flow Diagrams

## Complete System Flow (Mermaid)

```mermaid
graph TD
    START([System Start]) --> GLOBAL[Global Pre-Check]

    GLOBAL -->|All Pass| MODE{Mode Selection}
    GLOBAL -->|Any Fail| STOP1[STOP SYSTEM]

    MODE -->|OPTIONS_INTRADAY| OPTIONS[Phase 1: Options Analysis]
    MODE -->|SWING_LONG| SWING[Phase 1: Swing Analysis]

    OPTIONS --> HTF15[15m Regime Check]
    HTF15 -->|TREND/EXPANSION| MTF5[5m Direction & Momentum]
    HTF15 -->|RANGE/CHOP| NO_TRADE1[NO_TRADE]

    MTF5 -->|Aligned| LTF1[1m Entry Trigger]
    MTF5 -->|Not Aligned| NO_TRADE2[NO_TRADE]

    LTF1 --> STRIKE[Strike Selection]
    STRIKE -->|Valid| SYNTHESIS1[Synthesis TradePlan]
    STRIKE -->|Invalid| NO_TRADE3[NO_TRADE]

    SWING --> HTF1D[1D Trend Check]
    HTF1D -->|UP/DOWN| MTF1H[1H Setup]
    HTF1D -->|SIDEWAYS| NO_TRADE4[NO_TRADE]

    MTF1H -->|Valid Setup| LTF15[15m Entry Zone]
    MTF1H -->|No Setup| NO_TRADE5[NO_TRADE]

    LTF15 --> SYNTHESIS2[Synthesis TradePlan]

    SYNTHESIS1 --> PHASE2[Phase 2: Agent B Validation]
    SYNTHESIS2 --> PHASE2

    PHASE2 --> CAPITAL[Capital & Risk Check]
    CAPITAL --> SL_VAL[SL Validation]
    SL_VAL -->|Within Caps| LOT[Lot Size Calculation]
    SL_VAL -->|Exceeds Caps| REJECT1[REJECT]

    LOT -->|Lots >= 1| TP_VAL[TP Validation]
    LOT -->|Lots < 1| REJECT2[REJECT]

    TP_VAL -->|RR >= 1.5| PLAN[Executable Plan]
    TP_VAL -->|RR < 1.5| REJECT3[REJECT]

    PLAN --> PHASE3[Phase 3: Agent C Execution]

    PHASE3 --> PRE_EXEC[Pre-Execution Checks]
    PRE_EXEC -->|All Pass| EXECUTE[Place Order]
    PRE_EXEC -->|Any Fail| STOP2[STOP & ALERT]

    EXECUTE -->|Success| PHASE4[Phase 4: Position Tracking]
    EXECUTE -->|Failure| STOP3[STOP & ALERT]

    PHASE4 --> INIT[Position Initialization]
    INIT --> LIVE[Live Management]
    LIVE --> MONITOR[Monitor Position]

    MONITOR -->|Exit Triggered| PHASE5[Phase 5: Completion]
    MONITOR -->|Continue| LIVE

    PHASE5 --> JOURNAL[Journal & Metrics]
    JOURNAL --> IDLE[Return to IDLE]

    NO_TRADE1 --> IDLE
    NO_TRADE2 --> IDLE
    NO_TRADE3 --> IDLE
    NO_TRADE4 --> IDLE
    NO_TRADE5 --> IDLE
    REJECT1 --> IDLE
    REJECT2 --> IDLE
    REJECT3 --> IDLE
    STOP1 --> HALT[SYSTEM HALT]
    STOP2 --> HALT
    STOP3 --> HALT

    style STOP1 fill:#ff6b6b
    style STOP2 fill:#ff6b6b
    style STOP3 fill:#ff6b6b
    style HALT fill:#ff6b6b
    style NO_TRADE1 fill:#ffd93d
    style NO_TRADE2 fill:#ffd93d
    style NO_TRADE3 fill:#ffd93d
    style NO_TRADE4 fill:#ffd93d
    style NO_TRADE5 fill:#ffd93d
    style REJECT1 fill:#ffd93d
    style REJECT2 fill:#ffd93d
    style REJECT3 fill:#ffd93d
    style EXECUTE fill:#6bcf7f
    style IDLE fill:#95e1d3
```

## Phase 1: Agent A Flow (Options Intraday)

```mermaid
graph TD
    START[Phase 1 Start] --> MODE_CHECK{Mode Valid?}
    MODE_CHECK -->|No| STOP[STOP]
    MODE_CHECK -->|Yes| HTF[15m Regime Analysis]

    HTF --> REGIME{Regime?}
    REGIME -->|TREND| MTF[5m Direction & Momentum]
    REGIME -->|EXPANSION| MTF
    REGIME -->|RANGE| NO_TRADE1[NO_TRADE]
    REGIME -->|CHOP| NO_TRADE1

    MTF --> DIRECTION{Direction?}
    DIRECTION -->|BULLISH| MOMENTUM{Momentum?}
    DIRECTION -->|BEARISH| MOMENTUM
    DIRECTION -->|NEUTRAL| NO_TRADE2[NO_TRADE]

    MOMENTUM --> ALIGN{Aligned with HTF?}
    ALIGN -->|No| NO_TRADE3[NO_TRADE]
    ALIGN -->|Yes| LTF[1m Entry Trigger]

    LTF --> ENTRY{Entry Type?}
    ENTRY -->|BREAKOUT| STRIKE[Strike Selection]
    ENTRY -->|PULLBACK| STRIKE

    STRIKE --> DIR_CEPE{CE or PE?}
    DIR_CEPE -->|CE| ATM[Find ATM Strike]
    DIR_CEPE -->|PE| ATM

    ATM --> FILTERS[Apply Filters]
    FILTERS --> REGIME_FILTER{Regime Filter}
    REGIME_FILTER -->|Pass| MOM_FILTER{Momentum Filter}
    REGIME_FILTER -->|Fail| NO_TRADE4[NO_TRADE]

    MOM_FILTER -->|Pass| VOL_FILTER{Volatility Filter}
    MOM_FILTER -->|Fail| NO_TRADE5[NO_TRADE]

    VOL_FILTER -->|Pass| TIME_FILTER{Time Filter}
    VOL_FILTER -->|Fail| NO_TRADE6[NO_TRADE]

    TIME_FILTER -->|Pass| CANDIDATES[Strike Candidates]
    TIME_FILTER -->|Fail| NO_TRADE7[NO_TRADE]

    CANDIDATES --> OUTPUT[TradePlan Output]
    OUTPUT --> END[Phase 1 Complete]

    NO_TRADE1 --> END
    NO_TRADE2 --> END
    NO_TRADE3 --> END
    NO_TRADE4 --> END
    NO_TRADE5 --> END
    NO_TRADE6 --> END
    NO_TRADE7 --> END
    STOP --> END

    style NO_TRADE1 fill:#ffd93d
    style NO_TRADE2 fill:#ffd93d
    style NO_TRADE3 fill:#ffd93d
    style NO_TRADE4 fill:#ffd93d
    style NO_TRADE5 fill:#ffd93d
    style NO_TRADE6 fill:#ffd93d
    style NO_TRADE7 fill:#ffd93d
    style STOP fill:#ff6b6b
    style OUTPUT fill:#6bcf7f
```

## Phase 2: Agent B Flow (Risk Validation)

```mermaid
graph TD
    START[Phase 2 Start] --> CAPITAL[Capital & Risk Check]
    CAPITAL --> FUNDS{Funds Available?}
    FUNDS -->|No| REJECT1[REJECT]
    FUNDS -->|Yes| SL_CONVERT[Convert SL Logic to Price]

    SL_CONVERT --> SL_CALC[Calculate SL %]
    SL_CALC --> SL_CHECK{SL <= Max?}
    SL_CHECK -->|NIFTY > 30%| REJECT2[REJECT]
    SL_CHECK -->|SENSEX > 25%| REJECT2
    SL_CHECK -->|Within Cap| LOT_CALC[Calculate Lot Size]

    LOT_CALC --> RISK_PER_LOT[Risk per Lot]
    RISK_PER_LOT --> ALLOWED_LOTS[Allowed Lots = floor(max_risk / risk_per_lot)]
    ALLOWED_LOTS --> LOT_CHECK{Lots >= 1?}
    LOT_CHECK -->|No| REJECT3[REJECT]
    LOT_CHECK -->|Yes| MAX_LOT{<= Max 6?}

    MAX_LOT -->|No| CAP_LOT[Cap at 6 Lots]
    MAX_LOT -->|Yes| TP_CONVERT[Convert TP Logic to Prices]
    CAP_LOT --> TP_CONVERT

    TP_CONVERT --> PARTIAL[Partial TP: 1.2x RR]
    PARTIAL --> FINAL[Final TP: 2.0x RR]
    FINAL --> RR_CHECK{RR >= Min?}

    RR_CHECK -->|No| REJECT4[REJECT]
    RR_CHECK -->|Yes| PLAN[Create Executable Plan]

    PLAN --> VALIDATE{All Fields Present?}
    VALIDATE -->|No| REJECT5[REJECT]
    VALIDATE -->|Yes| APPROVED[APPROVED]

    APPROVED --> END[Phase 2 Complete]
    REJECT1 --> END
    REJECT2 --> END
    REJECT3 --> END
    REJECT4 --> END
    REJECT5 --> END

    style REJECT1 fill:#ffd93d
    style REJECT2 fill:#ffd93d
    style REJECT3 fill:#ffd93d
    style REJECT4 fill:#ffd93d
    style REJECT5 fill:#ffd93d
    style APPROVED fill:#6bcf7f
```

## Phase 3: Agent C Flow (Execution)

```mermaid
graph TD
    START[Phase 3 Start] --> APPROVED{Trade Approved?}
    APPROVED -->|No| STOP1[STOP & ALERT]
    APPROVED -->|Yes| DUPLICATE{Duplicate Order?}

    DUPLICATE -->|Yes| STOP2[STOP & ALERT]
    DUPLICATE -->|No| ORDER_TYPE{Order Type Allowed?}

    ORDER_TYPE -->|No| STOP3[STOP & ALERT]
    ORDER_TYPE -->|Yes| DRY_RUN{Dry Run?}

    DRY_RUN -->|Yes| SIMULATE[Simulate Order]
    DRY_RUN -->|No| PLACE[Place Super Order]

    SIMULATE --> SUCCESS1[Success]
    PLACE --> RESULT{Order Result?}

    RESULT -->|Success| ORDER_ID[Order ID Returned]
    RESULT -->|Failure| STOP4[STOP & ALERT]

    ORDER_ID --> END[Phase 3 Complete]
    SUCCESS1 --> END
    STOP1 --> END
    STOP2 --> END
    STOP3 --> END
    STOP4 --> END

    style STOP1 fill:#ff6b6b
    style STOP2 fill:#ff6b6b
    style STOP3 fill:#ff6b6b
    style STOP4 fill:#ff6b6b
    style ORDER_ID fill:#6bcf7f
    style SUCCESS1 fill:#6bcf7f
```

## Hard System Kill Conditions

```mermaid
graph TD
    MONITOR[System Monitoring] --> CHECK1{Max Daily Loss?}
    CHECK1 -->|Breached| HALT1[IMMEDIATE HALT]
    CHECK1 -->|OK| CHECK2{WS Disconnected?}

    CHECK2 -->|Yes + Position| HALT2[IMMEDIATE HALT]
    CHECK2 -->|OK| CHECK3{Duplicate Execution?}

    CHECK3 -->|Detected| HALT3[IMMEDIATE HALT]
    CHECK3 -->|OK| CHECK4{Invalid State?}

    CHECK4 -->|Yes| HALT4[IMMEDIATE HALT]
    CHECK4 -->|OK| CHECK5{Unexpected LLM?}

    CHECK5 -->|Yes| HALT5[IMMEDIATE HALT]
    CHECK5 -->|OK| CONTINUE[Continue Normal Operation]

    HALT1 --> SHUTDOWN[System Shutdown]
    HALT2 --> SHUTDOWN
    HALT3 --> SHUTDOWN
    HALT4 --> SHUTDOWN
    HALT5 --> SHUTDOWN

    style HALT1 fill:#ff6b6b
    style HALT2 fill:#ff6b6b
    style HALT3 fill:#ff6b6b
    style HALT4 fill:#ff6b6b
    style HALT5 fill:#ff6b6b
    style SHUTDOWN fill:#ff6b6b
    style CONTINUE fill:#6bcf7f
```

## State Machine Overview

```mermaid
stateDiagram-v2
    [*] --> IDLE: System Start
    IDLE --> GLOBAL_PRECHECK: Trigger Received
    GLOBAL_PRECHECK --> IDLE: Pre-Check Failed
    GLOBAL_PRECHECK --> PHASE_1: Pre-Check Passed

    PHASE_1 --> IDLE: NO_TRADE
    PHASE_1 --> PHASE_2: TradePlan Generated

    PHASE_2 --> IDLE: REJECTED
    PHASE_2 --> PHASE_3: APPROVED

    PHASE_3 --> IDLE: Execution Failed
    PHASE_3 --> PHASE_4: Order Placed

    PHASE_4 --> PHASE_5: Exit Triggered
    PHASE_4 --> PHASE_4: Monitoring

    PHASE_5 --> IDLE: Journal Complete

    IDLE --> HALT: Kill Condition
    PHASE_1 --> HALT: Kill Condition
    PHASE_2 --> HALT: Kill Condition
    PHASE_3 --> HALT: Kill Condition
    PHASE_4 --> HALT: Kill Condition

    HALT --> [*]: System Shutdown
```

## Checklist Validation Flow

```mermaid
graph LR
    INPUT[Input Data] --> GUARD[ChecklistGuard]
    GUARD --> CHECK1[Check 1]
    CHECK1 -->|Pass| CHECK2[Check 2]
    CHECK1 -->|Fail| FAIL[Record Failure]

    CHECK2 -->|Pass| CHECK3[Check 3]
    CHECK2 -->|Fail| FAIL

    CHECK3 -->|Pass| CHECKN[Check N]
    CHECK3 -->|Fail| FAIL

    CHECKN -->|Pass| RESULT[All Passed]
    CHECKN -->|Fail| FAIL

    FAIL --> ACTION{Required?}
    ACTION -->|Yes| REJECT[REJECT/STOP]
    ACTION -->|No| WARN[Warning Only]

    RESULT --> APPROVE[APPROVE]

    style FAIL fill:#ffd93d
    style REJECT fill:#ff6b6b
    style APPROVE fill:#6bcf7f
```

