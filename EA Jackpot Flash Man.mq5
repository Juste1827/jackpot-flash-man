//+------------------------------------------------------------------+
//|                                     JACKPOT FLASH MAN V4.0.mq5   |
//|        Copyright 2026, Juste Compaore - Zeubtologie Edition      |
//|                     Version 4.0 - Avec Quick Exit & Multi-Basket|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Juste Compaore - Zeubtologie Edition"
#property link      "https://webtic.agency"
#property version   "4.00"
#property description "JACKPOT FLASH MAN V4.0 - Moteur HFT + DOM + Rejection Block + Quick Exit + Multi-Basket"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== ⚙️ CONFIGURATION DE BASE & TYPE DE COMPTE ==="
input bool        InpAutoDetectAccountType= true;   // Auto-détection (Standard vs Cent)
input bool        InpIsCentAccount        = false;  // Actif si Auto-détection est désactivée
input bool        InpAutoAssetConfig      = true;   // Auto-config selon l'actif
input int         InpBaseMagicNumber      = 999000; // Magic Number de base
input double      InpBaseEquityForScaling = 50.0;   // Équité de référence en USD ($50)

input group "=== 🧠 MOTEUR DE MICRO-STRUCTURE ==="
input int         InpEMAPeriod            = 21;     // Période EMA de tendance
input int         InpATRPeriod            = 14;     // Période ATR pour volatilité
input int         InpTickConsecutiveReq   = 3;      // Ticks consécutifs requis
input double      InpMaxCandleAmplitudePct= 0.80;   // Bloquer entrée si bougie > 80% ATR

input group "===  RAFALES & COOLDOWN ==="
input int         InpCooldownSec          = 5;      // Cooldown minimum entre rafales (sec)
input int         InpMaxPositions         = 15;     // Max positions simultanées (sera ajusté dynamiquement)
input double      InpAccountThresholdUSD  = 350.0;  // Seuil de solde pour passer de 3 à 5 en 1ère rafale
input double      InpMaxSpreadPctOfATR    = 0.50;   // Spread max autorisé (% ATR)

input group "=== 🛡️ GESTION DU RISQUE & PONDÉRATION DE LOTS ==="
input double      InpRiskPercentPerRafale = 1.0;    // Risque % total par rafale (si équité >= $500)
input double      InpMicroAccountRiskUSD  = 25.0;   // Tranche USD pour 0.01 lot
input double      InpMarginBudgetPct      = 80.0;   // Budget de marge max disponible (%)
input double      InpMinLot               = 0.01;   
input double      InpMaxLot               = 50.0;   

input group "=== 🎯 OBJECTIFS PANIER & BOUCLIER UNIVERSEL V4 ==="
input double      InpBaseMicroTriggerUSD  = 2.0;    // Seuil d'activation Micro-Bouclier (<700$: $2, >=700$: $4)
input double      InpBaseMacroTargetUSD   = 5.0;    // Cible Macro Globale ($5.0 pour $50)
input double      InpShieldRetracePct     = 5.0;    // Retracement toléré Bouclier (5% -> Sécurise 95%)
input int         InpStagnationSec        = 15;     // Clôture si profit stagne/baisse depuis X sec

input group "=== 🚀 QUICK EXIT MICRO-GAINS ==="
input double      InpQuickExitMinUSD      = 0.50;   // Profit minimum pour Quick Exit
input int         InpQuickExitStagnSec    = 10;     // Secondes de stagnation avant Quick Exit

input group "=== 🧬 MOTEUR TICK-MICROSTRUCTURE (EXPÉRIMENTAL) ==="
input bool         InpUseTickMicroEngine   = false;  // true = moteur tick (rapide) / false = moteur M1 historique
input int          InpTickEMAPeriod        = 20;     // Période EMA calculée sur les ticks (pas M1)
input int          InpTickSlopeLookback    = 5;      // Nb de ticks en arrière pour mesurer la pente de l'EMA
input int          InpTickDeltaWindow      = 10;     // Fenêtre glissante du delta pondéré par fréquence
input double       InpTickDeltaRatioThresh = 0.60;   // Ratio mini |delta|/poids total pour valider (anti-spoof)
input int          InpMaxTickIntervalMs    = 800;    // Seuil de secours (avant que la moyenne glissante soit établie)
input double       InpMaxTickIntervalFactor= 4.0;    // Bloque si l'intervalle courant > ce multiple de la moyenne glissante (adaptatif par instrument)
input double       InpMinSlopeToATRRatio   = 0.05;   // Pente mini = % de l'ATR M1 courant (filtre le bruit hors-volatilité)

input group "=== 🧠 MOTEUR DE PRÉDICTION (LE CERVEAU) - EXPÉRIMENTAL ==="
input bool         InpUsePredictiveEngine   = true;  // Active la couche Cerveau (régime + phase de bougie + anti-spoof)
input int          InpSerenityRegressionBars= 20;     // Nb de bougies M1 clôturées pour la régression (pente de tendance)
input double       InpSerenityMinSlopeToATR = 0.15;   // Pente mini (ratio ATR) pour déclarer un régime STRICT
input double        InpSerenityMinR2        = 0.35;   // Qualité mini de régression (R²) - évite un régime "strict" sur du bruit
input int          InpCandlePhase1EndSec    = 15;     // Fin de la phase Accumulation (secondes depuis l'ouverture M1)
input int          InpCandlePhase2EndSec    = 40;     // Fin de la phase Impulsion / début Distribution
input double       InpShieldRetracePctHold  = 5.0;   // Tolérance de retracement ÉLARGIE pendant un Hold (jamais désactivée)
input double       InpDeltaSpreadMaxDivPts  = 15.0;   // Divergence max |ΔBid-ΔAsk| en points avant blocage anti-spoof

// ==================== FILTRES SUPPLÉMENTAIRES ====================
input group "===  FILTRES DOM & REJECTION BLOCK ==="
input bool         InpUseDOMFilter          = true;   // Activer le filtre Profondeur de Marché (DOM)
input int          InpDOMDepth              = 5;      // Nb de niveaux DOM analysés
input double       InpDOMRatioBuy           = 1.2;    // Ratio Bid/Ask min pour achat (seuil large)
input double       InpDOMRatioSell          = 0.83;   // Ratio Ask/Bid min pour vente (1/1.2)
input bool         InpUseRejectionBlock     = true;   // Activer le Rejection Block (anti-fakeout)
input int          InpRejectionWaitSec      = 1;      // Temps d'attente (secondes) avant validation
input double       InpRejectionRetracePct   = 25.0;   // % de retracement max autorisé (par rapport au range de référence)
input bool         InpRejectionUsePrevCandle= true;   // true = range bougie M1 précédente, false = ATR*0.5
input bool         InpRejectionOnlyForM1    = false;  // true = appliquer seulement au moteur M1 (pas au tick)

input group "=== 🛑 ANTI-MARTINGALE ==="
input int          InpMaxConsecutiveLosses = 3;      // Pause après X pertes consécutives
input int          InpPauseAfterLossesMin  = 5;      // Durée de la pause en minutes

input group "=== 🖥️ DASHBOARD PREMIUM ==="
input bool        InpShowDashboard        = true;   // Afficher le tableau de bord
input int         InpDashX                = 15;     // Position X (pixels)
input int         InpDashY                = 15;     // Position Y (pixels)
input color       InpDashBgColor          = clrBlack;      // Couleur de fond
input color       InpDashBorderColor      = clrGold;       // Couleur de la bordure
input color       InpDashTextColor        = clrWhite;      // Couleur du texte principal
input color       InpDashHighlightColor   = clrGold;       // Couleur des titres

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
int      Magic = 999999;
int      handleEMA, handleATR;
double   g_maxSpread = 35; 
bool     g_isCentAccount = false;
string   prefixObj = "JFM_V4_";

// Structure pour stocker les ticks
struct TickData {
   double bid;
   double ask;
   long   volume;
   long   time_msc;
};
TickData g_tickBuffer[];
int      g_tickIdx = 0;
ulong    g_lastTradeTime = 0;

double   g_currentVWAP = 0;
bool     g_isNewsTime  = false;

// Variables du Bouclier et Paniers (Multi-Basket)
struct BasketData {
   int id;
   double peakProfit;
   double currentProfit;
   int posCount;
   datetime timeOfPeak;
};
BasketData g_baskets[2];

// Anti-Martingale
int g_consecutiveLosses = 0;
datetime g_lastLossTime = 0;
double g_lastBasketProfit = 0.0;

//+------------------------------------------------------------------+
//| MOTEUR TICK-MICROSTRUCTURE                                       |
//+------------------------------------------------------------------+
enum ENUM_MICRO_STATE { STATE_NEUTRAL=0, STATE_BUY_BIAS=1, STATE_SELL_BIAS=-1 };
ENUM_MICRO_STATE g_microState = STATE_NEUTRAL;

double   g_tickEMA             = 0.0;
bool     g_tickEMAInit         = false;
double   g_emaHistory[];        
int      g_emaHistIdx          = 0;
double   g_deltaHistory[];      
double   g_absWeightHistory[];  
int      g_deltaHistIdx        = 0;
double   g_rollingDeltaSum     = 0.0;
double   g_rollingAbsWeightSum = 0.0;
double   g_lastTickPrice       = 0.0;
ulong    g_lastTickMsc         = 0;
double   g_avgTickIntervalMs   = 0.0;

//+------------------------------------------------------------------+
//| MOTEUR DE PRÉDICTION (LE CERVEAU)                                |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME { REGIME_NEUTRAL=0, REGIME_STRICT_BULL=1, REGIME_STRICT_BEAR=-1 };
ENUM_MARKET_REGIME g_marketRegime = REGIME_NEUTRAL;

enum ENUM_CANDLE_PHASE { PHASE_ACCUMULATION=0, PHASE_IMPULSION=1, PHASE_DISTRIBUTION=2 };
ENUM_CANDLE_PHASE g_candlePhase = PHASE_ACCUMULATION;

double g_pivotPoint          = 0.0;
double g_prevBidForDeltaSpread = 0.0;
double g_prevAskForDeltaSpread = 0.0;
datetime g_lastCerebrumBar = 0;

// ==================== VARIABLES POUR FILTRES ====================
// DOM - variable interne pour permettre la désactivation dynamique
bool   g_useDOMFilter = true;    // variable interne recopiée depuis l'input
double g_domRatio = 1.0;
bool   g_domReady = false;
int    g_domDepthActual = 0;

// Rejection Block
bool   g_rejWaiting = false;
ulong  g_rejStartTime = 0;
double g_rejEntryPrice = 0;
int    g_rejDirection = 0;    // 1 = buy, -1 = sell
double g_rejRange = 0;
double g_rejATR = 0;
bool   g_rejActive = false;

//+------------------------------------------------------------------+
//| PROTOTYPES DES FONCTIONS                                         |
//+------------------------------------------------------------------+
void   InitBaskets();
void   ManageBaskets(double atr);
int    AnalyzeMicroStructure(const MqlTick &tick, double ema, double vwap, double atr);
int    AnalyzeTickMicroStructure(const MqlTick &tick, double atr);
bool   HasPositionType(ENUM_POSITION_TYPE type);
void   GetSerenityScore(double atr);
void   GetCandlePhase();
void   PredictiveEngine(double atr);
bool   DeltaSpreadOK(const MqlTick &tick);
double CalculateBaseLot(double atr, ENUM_ORDER_TYPE orderType);
void   ExecuteRafale(ENUM_ORDER_TYPE type, double atr, int currentPositionsCount);
void   UpdateBackgroundMetrics();
void   CreateDashboard();
void   UpdateDashboard();
void   CloseAllPositions();
void   ClosePositionsByType(ENUM_POSITION_TYPE type);
void   CloseAllPositionsInBasket(int basketId);
int    PositionsTotalByMagic();
bool   CheckDOMFilter(int signal);
void   StartRejectionBlock(int signal, double atr);
void   ResetRejectionBlock();
void   ExecutePendingTradeIfValid(double atr);
void   ExecuteTradeLogic(int signal, double atr, int currentTotalPos);
void   ShiftBaskets();
int    GetDynamicCooldown(double currentATR);
void   CheckConsecutiveLosses();

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Alert("⚠️ ERREUR: Compte HEDGING requis pour JACKPOT FLASH MAN.");
      return(INIT_FAILED);
   }

   // 1. Détection dynamique du type de compte
   if(InpAutoDetectAccountType) {
      string currency = AccountInfoString(ACCOUNT_CURRENCY);
      StringToUpper(currency);
      g_isCentAccount = (StringFind(currency, "CENT") >= 0 || StringFind(currency, "USC") >= 0 || StringFind(currency, "EUC") >= 0);
   } else {
      g_isCentAccount = InpIsCentAccount;
   }

   // 2. Configuration selon le symbole
   string sym = _Symbol;
   StringToUpper(sym);

   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0) {
      Magic = InpBaseMagicNumber + 1; 
      g_maxSpread = 35; 
   } else if(StringFind(sym, "BTC") >= 0) {
      Magic = InpBaseMagicNumber + 2; 
      g_maxSpread = 1000; 
   } else if(StringFind(sym, "ETH") >= 0) {
      Magic = InpBaseMagicNumber + 3; 
      g_maxSpread = 100; 
   } else {
      Magic = InpBaseMagicNumber + 9; 
      g_maxSpread = 50;
   }

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(30);

   handleEMA = iMA(_Symbol, PERIOD_M1, InpEMAPeriod, 0, MODE_EMA, PRICE_TYPICAL);
   handleATR = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   if(handleEMA == INVALID_HANDLE || handleATR == INVALID_HANDLE) {
      Print("❌ Échec initialisation des indicateurs");
      return(INIT_FAILED);
   }

   ArrayResize(g_tickBuffer, 10);
   InitBaskets();

   // --- Souscription au carnet d'ordres pour le DOM avec variable interne ---
   g_useDOMFilter = InpUseDOMFilter;   // recopie de l'input
   if(g_useDOMFilter) {
      if(!MarketBookAdd(_Symbol)) {
         Print("⚠️ Impossible de souscrire au carnet d'ordres pour ", _Symbol);
         g_useDOMFilter = false;        // désactivation silencieuse
      } else {
         Print("✅ Souscription DOM active pour ", _Symbol);
      }
   }

   EventSetTimer(1);
   
   if(InpShowDashboard) {
      CreateDashboard();
   }

   PrintFormat("✅ JACKPOT FLASH MAN V4.0 Initialisé | Compte: %s | Max Pos: %d | Magic: %d", 
               g_isCentAccount ? "CENT" : "STANDARD", InpMaxPositions, Magic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   IndicatorRelease(handleEMA);
   IndicatorRelease(handleATR);
   if(g_useDOMFilter) {
      MarketBookRelease(_Symbol);
   }
   if(InpShowDashboard) {
      ObjectsDeleteAll(0, prefixObj);
   }
}

//+------------------------------------------------------------------+
//| TIMER                                                            |
//+------------------------------------------------------------------+
void OnTimer() {
   UpdateBackgroundMetrics();
   
   // Cerveau : Calcul uniquement sur nouvelle bougie M1 (optimisation CPU)
   if(InpUsePredictiveEngine) {
      datetime currentBar = iTime(_Symbol, PERIOD_M1, 0);
      if(currentBar != g_lastCerebrumBar) {
         g_lastCerebrumBar = currentBar;
         double atrBuf[];
         if(CopyBuffer(handleATR, 0, 1, 1, atrBuf) > 0) {
            PredictiveEngine(atrBuf[0]);
         }
      }
   }
   
   if(InpShowDashboard) {
      UpdateDashboard();
   }
   
   CheckConsecutiveLosses();
}

//+------------------------------------------------------------------+
//| GESTION DES ÉVÉNEMENTS DU CARNET (DOM)                          |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol) {
   if(symbol != _Symbol) return;
   if(!g_useDOMFilter) return;
   
   MqlBookInfo book[];
   if(MarketBookGet(_Symbol, book)) {
      static bool firstCall = true;
      if(firstCall) {
         g_domDepthActual = ArraySize(book);
         Print("📊 Profondeur DOM reçue pour ", _Symbol, " : ", g_domDepthActual, " niveaux");
         firstCall = false;
      }
      
      double bidVol = 0.0, askVol = 0.0;
      int count = MathMin(InpDOMDepth, ArraySize(book));
      for(int i=0; i<count; i++) {
         if(book[i].type == BOOK_TYPE_BUY) bidVol += (double)book[i].volume;
         else if(book[i].type == BOOK_TYPE_SELL) askVol += (double)book[i].volume;
      }
      if(askVol > 0.0) g_domRatio = bidVol / askVol;
      else g_domRatio = (bidVol > 0.0) ? 999.0 : 1.0;
      g_domReady = true;
   }
}

//+------------------------------------------------------------------+
//| FONCTION PRINCIPALE ONTICK                                       |
//+------------------------------------------------------------------+
void OnTick() {
   if(g_isNewsTime) return;

      // 1. Anti-Martingale Check
   if(g_consecutiveLosses >= InpMaxConsecutiveLosses) {
      if((TimeCurrent() - g_lastLossTime) < (InpPauseAfterLossesMin * 60)) return;
      else {
         g_consecutiveLosses = 0;
         g_lastLossTime = 0; // CRUCIAL : réinitialiser pour éviter la réactivation immédiate
      }
   }

   MqlTick currentTick;
   if(!SymbolInfoTick(_Symbol, currentTick)) return;

   double atr[], ema[];
   if(CopyBuffer(handleATR, 0, 1, 1, atr) <= 0 || CopyBuffer(handleEMA, 0, 1, 1, ema) <= 0) return;

   double currentATR = atr[0];
   double currentEMA = ema[0];

   if(currentATR <= 0) return;

   // Filtre Spread
   double spreadInPrice = (currentTick.ask - currentTick.bid);
   if((spreadInPrice / currentATR) > InpMaxSpreadPctOfATR) return;

   // 1. Gestion des Paniers (Quick Exit, Bouclier, Shift)
   ManageBaskets(currentATR);

   // 2. Cooldown Dynamique
   int cooldownMs = GetDynamicCooldown(currentATR);
   if((GetTickCount64() - g_lastTradeTime) < (ulong)cooldownMs) return;
   
   // 3. Limite de positions dynamique selon l'équité
   int currentTotalPos = 0;
   for(int i=0; i<2; i++) currentTotalPos += g_baskets[i].posCount;
   
   double effEquity = g_isCentAccount ? (AccountInfoDouble(ACCOUNT_EQUITY) / 100.0) : AccountInfoDouble(ACCOUNT_EQUITY);
   int maxAllowedPos = 8;
   if(effEquity < 100.0) maxAllowedPos = 3;
   else if(effEquity < 700.0) maxAllowedPos = 5;
   
   if(currentTotalPos >= maxAllowedPos) return;

   // 4. Gestion du Rejection Block (si en attente)
   if(InpUseRejectionBlock && g_rejWaiting) {
      ExecutePendingTradeIfValid(currentATR);
      return; // on ne génère pas de nouveau signal tant qu'on est en attente
   }

   // 5. Moteur de Micro-Structure
   int signal = InpUseTickMicroEngine
                ? AnalyzeTickMicroStructure(currentTick, currentATR)
                : AnalyzeMicroStructure(currentTick, currentEMA, g_currentVWAP, currentATR);

   if(signal == 0) return;

   // 6. Portes du Cerveau (si activé)
   bool phaseAllowsEntry = (!InpUsePredictiveEngine || g_candlePhase != PHASE_DISTRIBUTION);
   bool spreadOK = DeltaSpreadOK(currentTick);
   bool allowNewEntry = phaseAllowsEntry && spreadOK;
   if(!allowNewEntry) return;

   // 7. Filtre DOM (Profondeur de marché) - avec seuils larges
   if(g_useDOMFilter && !CheckDOMFilter(signal)) {
      return;
   }

   // 8. Rejection Block : décision d'activation sélective
   bool useRejection = InpUseRejectionBlock;
   if(useRejection && InpRejectionOnlyForM1 && InpUseTickMicroEngine) {
      // Si l'option "seulement pour M1" est active et qu'on utilise le moteur tick, on désactive le Rejection
      useRejection = false;
   }

   // 9. Exécution ou mise en attente selon Rejection Block
   if(useRejection) {
      StartRejectionBlock(signal, currentATR);
   } else {
      ExecuteTradeLogic(signal, currentATR, currentTotalPos);
   }
}

//+------------------------------------------------------------------+
//| LOGIQUE D'EXÉCUTION (factorisée)                                 |
//+------------------------------------------------------------------+
void ExecuteTradeLogic(int signal, double atr, int currentTotalPos) {
   if(signal == 1) {
      bool hadSell = HasPositionType(POSITION_TYPE_SELL);
      bool hadBuy  = HasPositionType(POSITION_TYPE_BUY);
      if(hadSell) {
         bool holdActive = InpUsePredictiveEngine && g_marketRegime == REGIME_STRICT_BEAR && SymbolInfoDouble(_Symbol, SYMBOL_BID) <= g_pivotPoint;
         if(!holdActive) {
            ClosePositionsByType(POSITION_TYPE_SELL);
            ExecuteRafale(ORDER_TYPE_BUY, atr, 0);
         }
      } else if(hadBuy) {
         if(g_lastBasketProfit >= 0.0) ExecuteRafale(ORDER_TYPE_BUY, atr, currentTotalPos);
      } else {
         ExecuteRafale(ORDER_TYPE_BUY, atr, currentTotalPos);
      }
   } else if(signal == -1) {
      bool hadBuy  = HasPositionType(POSITION_TYPE_BUY);
      bool hadSell = HasPositionType(POSITION_TYPE_SELL);
      if(hadBuy) {
         bool holdActive = InpUsePredictiveEngine && g_marketRegime == REGIME_STRICT_BULL && SymbolInfoDouble(_Symbol, SYMBOL_BID) >= g_pivotPoint;
         if(!holdActive) {
            ClosePositionsByType(POSITION_TYPE_BUY);
            ExecuteRafale(ORDER_TYPE_SELL, atr, 0);
         }
      } else if(hadSell) {
         if(g_lastBasketProfit >= 0.0) ExecuteRafale(ORDER_TYPE_SELL, atr, currentTotalPos);
      } else {
         ExecuteRafale(ORDER_TYPE_SELL, atr, currentTotalPos);
      }
   }
}

//+------------------------------------------------------------------+
//| FILTRE DOM                                                        |
//+------------------------------------------------------------------+
bool CheckDOMFilter(int signal) {
   if(!g_domReady) return true; // permissif par défaut
   if(signal == 1) {
      return (g_domRatio >= InpDOMRatioBuy);
   } else if(signal == -1) {
      return (g_domRatio <= InpDOMRatioSell);
   }
   return true;
}

//+------------------------------------------------------------------+
//| LANCEMENT DU REJECTION BLOCK                                     |
//+------------------------------------------------------------------+
void StartRejectionBlock(int signal, double atr) {
   g_rejWaiting = true;
   g_rejStartTime = GetTickCount64();
   g_rejDirection = signal;
   g_rejEntryPrice = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_rejATR = atr;
   g_rejActive = true;

   // Calcul du range de référence
   if(InpRejectionUsePrevCandle) {
      double highPrev = iHigh(_Symbol, PERIOD_M1, 1);
      double lowPrev  = iLow(_Symbol, PERIOD_M1, 1);
      g_rejRange = highPrev - lowPrev;
      if(g_rejRange < atr * 0.2) g_rejRange = atr * 0.5;
   } else {
      g_rejRange = atr * 0.5;
   }

   Print(" Rejection Block lancé pour signal ", signal, " | range de référence = ", g_rejRange);
}

//+------------------------------------------------------------------+
//| RÉINITIALISATION DU REJECTION BLOCK                              |
//+------------------------------------------------------------------+
void ResetRejectionBlock() {
   g_rejWaiting = false;
   g_rejStartTime = 0;
   g_rejDirection = 0;
   g_rejEntryPrice = 0;
   g_rejRange = 0;
   g_rejATR = 0;
   g_rejActive = false;
}

//+------------------------------------------------------------------+
//| EXÉCUTION DIFFÉRÉE DU REJECTION BLOCK                            |
//+------------------------------------------------------------------+
void ExecutePendingTradeIfValid(double atr) {
   if(!g_rejWaiting) return;

   ulong elapsed = (GetTickCount64() - g_rejStartTime) / 1000;
   if(elapsed < (ulong)InpRejectionWaitSec) return;

   // Temps écoulé, on vérifie le retracement
   double currentPrice = (g_rejDirection == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double range = g_rejRange;

   double retracePct = 0.0;
   if(g_rejDirection == 1) {
      retracePct = (g_rejEntryPrice - currentPrice) / range * 100.0;
   } else {
      retracePct = (currentPrice - g_rejEntryPrice) / range * 100.0;
   }

   bool retraceOK = (retracePct <= InpRejectionRetracePct);

   if(retraceOK) {
      Print("✅ Rejection Block validé pour signal ", g_rejDirection, " (retracement = ", DoubleToString(retracePct, 2), "%)");
      int currentTotalPos = 0;
      for(int i=0; i<2; i++) currentTotalPos += g_baskets[i].posCount;
      
      if(currentTotalPos < InpMaxPositions) {
         ExecuteTradeLogic(g_rejDirection, atr, currentTotalPos);
      }
   } else {
      Print("❌ Rejection Block annulé : retracement = ", DoubleToString(retracePct, 2), "% > ", InpRejectionRetracePct, "%");
   }

   ResetRejectionBlock();
}

//+------------------------------------------------------------------+
//| MOTEUR DE MICRO-STRUCTURE (M1 historique)                        |
//+------------------------------------------------------------------+
int AnalyzeMicroStructure(const MqlTick &tick, double ema, double vwap, double atr) {
   g_tickBuffer[g_tickIdx].bid = tick.bid;
   g_tickBuffer[g_tickIdx].ask = tick.ask;
   g_tickBuffer[g_tickIdx].volume = (long)tick.volume;
   g_tickBuffer[g_tickIdx].time_msc = (long)tick.time_msc;
   g_tickIdx = (g_tickIdx + 1) % 10;

   bool isBullishTrend = (tick.bid > vwap) && (tick.bid > ema);
   bool isBearishTrend = (tick.bid < vwap) && (tick.bid < ema);
   
   if(!isBullishTrend && !isBearishTrend) return 0;

   int consecutiveUp = 0, consecutiveDown = 0;
   for(int i = 1; i <= InpTickConsecutiveReq; i++) {
      int idx = (g_tickIdx - i + 10) % 10;
      int prevIdx = (g_tickIdx - i - 1 + 10) % 10;
      if(g_tickBuffer[idx].bid > g_tickBuffer[prevIdx].bid) consecutiveUp++;
      if(g_tickBuffer[idx].bid < g_tickBuffer[prevIdx].bid) consecutiveDown++;
   }

   double high = iHigh(_Symbol, PERIOD_M1, 0);
   double low  = iLow(_Symbol, PERIOD_M1, 0);
   if((high - low) > (atr * InpMaxCandleAmplitudePct)) return 0;

   if(isBullishTrend && consecutiveUp >= InpTickConsecutiveReq) return 1;
   if(isBearishTrend && consecutiveDown >= InpTickConsecutiveReq) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| MOTEUR TICK-MICROSTRUCTURE (expérimental)                        |
//+------------------------------------------------------------------+
int AnalyzeTickMicroStructure(const MqlTick &tick, double atr) {
   double price   = tick.bid;
   ulong  nowMsc  = (ulong)tick.time_msc;

   long intervalMs = (g_lastTickMsc == 0) ? 0 : (long)(nowMsc - g_lastTickMsc);
   g_lastTickMsc = nowMsc;
   if(g_lastTickPrice == 0.0) g_lastTickPrice = price;

   double blockThreshold;
   if(g_avgTickIntervalMs > 0.0) {
      blockThreshold = g_avgTickIntervalMs * InpMaxTickIntervalFactor;
   } else {
      blockThreshold = (double)InpMaxTickIntervalMs;
   }

   if(intervalMs > 0 && intervalMs < 60000) {
      g_avgTickIntervalMs = (g_avgTickIntervalMs <= 0.0) ? (double)intervalMs
                                                          : (g_avgTickIntervalMs * 0.95 + (double)intervalMs * 0.05);
   }

   if(intervalMs > (long)blockThreshold) {
      g_lastTickPrice = price;
      return 0;
   }

   double alpha = 2.0 / (InpTickEMAPeriod + 1);
   if(!g_tickEMAInit) { g_tickEMA = price; g_tickEMAInit = true; }
   else                 g_tickEMA = price * alpha + g_tickEMA * (1.0 - alpha);

   int histLen = ArraySize(g_emaHistory);
   int slopeIdx = (g_emaHistIdx - InpTickSlopeLookback + histLen) % histLen;
   double slope = g_tickEMA - g_emaHistory[slopeIdx];
   g_emaHistory[g_emaHistIdx] = g_tickEMA;
   g_emaHistIdx = (g_emaHistIdx + 1) % histLen;

   int direction = (price > g_lastTickPrice) ? 1 : (price < g_lastTickPrice ? -1 : 0);
   double weight = 1000.0 / (double)MathMax(1, intervalMs);
   g_lastTickPrice = price;

   int dWindow = ArraySize(g_deltaHistory);
   double oldDelta = g_deltaHistory[g_deltaHistIdx];
   double oldAbsW  = g_absWeightHistory[g_deltaHistIdx];
   double newDelta = (double)direction * weight;
   double newAbsW  = MathAbs(newDelta);

   g_rollingDeltaSum     += newDelta - oldDelta;
   g_rollingAbsWeightSum += newAbsW  - oldAbsW;
   g_deltaHistory[g_deltaHistIdx]     = newDelta;
   g_absWeightHistory[g_deltaHistIdx] = newAbsW;
   g_deltaHistIdx = (g_deltaHistIdx + 1) % dWindow;

   double deltaRatio = (g_rollingAbsWeightSum > 0) ? MathAbs(g_rollingDeltaSum) / g_rollingAbsWeightSum : 0.0;

   double minSlope = atr * InpMinSlopeToATRRatio;
   if(slope > minSlope && price > g_tickEMA)        g_microState = STATE_BUY_BIAS;
   else if(slope < -minSlope && price < g_tickEMA)  g_microState = STATE_SELL_BIAS;
   else                                              g_microState = STATE_NEUTRAL;

   if(g_microState == STATE_BUY_BIAS  && g_rollingDeltaSum > 0 && deltaRatio >= InpTickDeltaRatioThresh) return 1;
   if(g_microState == STATE_SELL_BIAS && g_rollingDeltaSum < 0 && deltaRatio >= InpTickDeltaRatioThresh) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| UTILITAIRE: vérifie s'il existe au moins une position ouverte    |
//+------------------------------------------------------------------+
bool HasPositionType(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE A : SCORE DE SÉRÉNITÉ (régression linéaire M1 + R²)       |
//+------------------------------------------------------------------+
void GetSerenityScore(double atr) {
   int n = InpSerenityRegressionBars;
   if(n < 3 || Bars(_Symbol, PERIOD_M1) < n + 1 || atr <= 0) { g_marketRegime = REGIME_NEUTRAL; return; }

   double prices[];
   ArrayResize(prices, n);
   double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
   for(int i = 0; i < n; i++) {
      int shift = n - i;
      prices[i] = (iHigh(_Symbol, PERIOD_M1, shift) + iLow(_Symbol, PERIOD_M1, shift) + iClose(_Symbol, PERIOD_M1, shift)) / 3.0;
      double x = (double)i;
      sumX += x; sumY += prices[i]; sumXY += x * prices[i]; sumXX += x * x;
   }

   double denom = (n * sumXX - sumX * sumX);
   if(denom == 0) { g_marketRegime = REGIME_NEUTRAL; return; }
   double slope     = (n * sumXY - sumX * sumY) / denom;
   double intercept = (sumY - slope * sumX) / n;

   double meanY = sumY / n, ssTot = 0, ssRes = 0;
   for(int i = 0; i < n; i++) {
      double predicted = intercept + slope * i;
      ssRes += MathPow(prices[i] - predicted, 2);
      ssTot += MathPow(prices[i] - meanY, 2);
   }
   double r2 = (ssTot > 0) ? (1.0 - ssRes / ssTot) : 0.0;
   double slopeToATR = (slope * n) / atr;

   if(r2 >= InpSerenityMinR2 && slopeToATR >= InpSerenityMinSlopeToATR)       g_marketRegime = REGIME_STRICT_BULL;
   else if(r2 >= InpSerenityMinR2 && slopeToATR <= -InpSerenityMinSlopeToATR) g_marketRegime = REGIME_STRICT_BEAR;
   else                                                                        g_marketRegime = REGIME_NEUTRAL;
}

//+------------------------------------------------------------------+
//| MODULE B : ANATOMIE DE LA BOUGIE M1 COURANTE                     |
//+------------------------------------------------------------------+
void GetCandlePhase() {
   datetime barOpen = iTime(_Symbol, PERIOD_M1, 0);
   int elapsedSec = (int)(TimeCurrent() - barOpen);

   if(elapsedSec < InpCandlePhase1EndSec)       g_candlePhase = PHASE_ACCUMULATION;
   else if(elapsedSec < InpCandlePhase2EndSec)  g_candlePhase = PHASE_IMPULSION;
   else                                          g_candlePhase = PHASE_DISTRIBUTION;
}

//+------------------------------------------------------------------+
//| ORCHESTRATEUR DU CERVEAU                                         |
//+------------------------------------------------------------------+
void PredictiveEngine(double atr) {
   GetSerenityScore(atr);
   GetCandlePhase();
   g_pivotPoint = (iHigh(_Symbol, PERIOD_M1, 1) + iLow(_Symbol, PERIOD_M1, 1) + iClose(_Symbol, PERIOD_M1, 1)) / 3.0;
}

//+------------------------------------------------------------------+
//| MODULE C : FILTRE ANTI-MANIPULATION (ΔBid ≈ ΔAsk)                |
//+------------------------------------------------------------------+
bool DeltaSpreadOK(const MqlTick &tick) {
   if(!InpUsePredictiveEngine) return true;
   if(g_prevBidForDeltaSpread == 0.0) {
      g_prevBidForDeltaSpread = tick.bid;
      g_prevAskForDeltaSpread = tick.ask;
      return true;
   }
   double deltaBid = tick.bid - g_prevBidForDeltaSpread;
   double deltaAsk = tick.ask - g_prevAskForDeltaSpread;
   g_prevBidForDeltaSpread = tick.bid;
   g_prevAskForDeltaSpread = tick.ask;
   double divergencePts = MathAbs(deltaBid - deltaAsk) / _Point;
   return divergencePts <= InpDeltaSpreadMaxDivPts;
}

//+------------------------------------------------------------------+
//| GESTION DES PANIERS MULTI-NIVEAUX + QUICK EXIT                   |
//+------------------------------------------------------------------+
void ManageBaskets(double atr) {
   // Réinitialisation des compteurs
   for(int i=0; i<2; i++) {
      g_baskets[i].currentProfit = 0;
      g_baskets[i].posCount = 0;
   }

   double effEquity = g_isCentAccount ? (AccountInfoDouble(ACCOUNT_EQUITY) / 100.0) : AccountInfoDouble(ACCOUNT_EQUITY);
   double shieldTrigger = (effEquity >= 700.0) ? 4.0 : 2.0;
   if(g_isCentAccount) shieldTrigger *= 100.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      int basketId = 0;
      if(StringFind(comment, "JFM_B2") >= 0) basketId = 1;
      
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      g_baskets[basketId].currentProfit += profit;
      g_baskets[basketId].posCount++;

      // Break-Even Individuel
      double beTrigger = atr * 1.0;
      double distInPrice = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
      
      if(distInPrice >= beTrigger) {
         double newSL = (type == POSITION_TYPE_BUY) ? openPrice + (atr * 0.1) : openPrice - (atr * 0.1);
         if((type == POSITION_TYPE_BUY && (currentSL < newSL)) || (type == POSITION_TYPE_SELL && (currentSL == 0 || currentSL > newSL))) {
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
         }
      }
   }

   // Logique Quick Exit + Bouclier par Panier
   for(int i=0; i<2; i++) {
      if(g_baskets[i].posCount == 0) {
         g_baskets[i].peakProfit = 0;
         continue;
      }

      double curProf = g_baskets[i].currentProfit;
      
      // Mise à jour du Pic
      if(curProf > g_baskets[i].peakProfit) {
         g_baskets[i].peakProfit = curProf;
         g_baskets[i].timeOfPeak = TimeCurrent();
      }

      //  QUICK EXIT POUR MICRO-GAINS (Avant armement du bouclier)
      if(curProf > InpQuickExitMinUSD && curProf < shieldTrigger) {
         if(curProf < g_baskets[i].peakProfit && (TimeCurrent() - g_baskets[i].timeOfPeak) >= InpQuickExitStagnSec) {
            PrintFormat("⚡ QUICK EXIT Micro-Gain ! Panier %d cloturé à %.2f$", i+1, curProf);
            CloseAllPositionsInBasket(i);
            g_baskets[i].peakProfit = 0;
            continue;
         }
      }

      // Activation et Déclenchement du Bouclier (Une fois le seuil atteint)
      if(g_baskets[i].peakProfit >= shieldTrigger) {
         double floor = g_baskets[i].peakProfit * (1.0 - (InpShieldRetracePct / 100.0));
         
         // Condition 1 : Retracement de 5%
         bool hitRetrace = (curProf <= floor);
         
         // Condition 2 : Stagnation (profit a baissé ou stagne depuis X secondes)
         bool isStagnant = (curProf < g_baskets[i].peakProfit) && ((TimeCurrent() - g_baskets[i].timeOfPeak) >= InpStagnationSec);

         if(hitRetrace || isStagnant) {
            CloseAllPositionsInBasket(i);
            g_baskets[i].peakProfit = 0;
         }
      }
   }

   g_lastBasketProfit = g_baskets[0].currentProfit + g_baskets[1].currentProfit;
   
   // Shift des Paniers (Si B1 est vide mais B2 a des positions, B2 devient B1)
   ShiftBaskets();
}

//+------------------------------------------------------------------+
//| DÉCALAGE DES PANIERS                                             |
//+------------------------------------------------------------------+
void ShiftBaskets() {
   if(g_baskets[0].posCount == 0 && g_baskets[1].posCount > 0) {
      // On renomme les positions du panier 2 en panier 1
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != Magic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         
         if(StringFind(PositionGetString(POSITION_COMMENT), "JFM_B2") >= 0) {
            MqlTradeRequest req = {};
            MqlTradeResult res = {};
            req.action = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.sl = PositionGetDouble(POSITION_SL);
            req.tp = PositionGetDouble(POSITION_TP);
            if(!OrderSend(req, res)) Print("⚠️ Échec renommage panier: ", GetLastError());
         }
      }
      // Transfert des données
      g_baskets[0] = g_baskets[1];
      g_baskets[1].id = 2;
      g_baskets[1].peakProfit = 0;
      g_baskets[1].currentProfit = 0;
      g_baskets[1].posCount = 0;
      g_baskets[1].timeOfPeak = 0;
   }
}

//+------------------------------------------------------------------+
//| CALCUL DU LOT GLOBAL THÉORIQUE                                   |
//+------------------------------------------------------------------+
double CalculateBaseLot(double atr, ENUM_ORDER_TYPE orderType) {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lot = InpMinLot;
   double effectiveEquityUSD = g_isCentAccount ? (equity / 100.0) : equity;

   if(effectiveEquityUSD < 500.0) {
      double scaleFactor = effectiveEquityUSD / MathMax(1.0, InpMicroAccountRiskUSD);
      lot = MathFloor(scaleFactor) * 0.01;
      if(g_isCentAccount) lot *= 100.0;
   } else {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double slDistance = atr * 1.2;

      if(tickSize > 0 && tickValue > 0 && slDistance > 0) {
         double riskAmountUSD = equity * (InpRiskPercentPerRafale / 100.0);
         double riskInPoints = slDistance / _Point;
         lot = riskAmountUSD / ((riskInPoints * _Point / tickSize) * tickValue);
      }
   }

   double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   double availableMargin = (equity * (InpMarginBudgetPct / 100.0)) - usedMargin;
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double marginForOneLot = 0;

   if(OrderCalcMargin(orderType, _Symbol, 1.0, price, marginForOneLot) && marginForOneLot > 0) {
      double maxAffordableLot = availableMargin / marginForOneLot;
      lot = MathMin(lot, maxAffordableLot);
   }

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVal = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVal = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;

   lot = MathRound(lot / step) * step;
   return MathMax(InpMinLot, MathMax(minVal, MathMin(maxVal, MathMin(InpMaxLot, lot))));
}

//+------------------------------------------------------------------+
//| MOTEUR DE RAFALE INTELLIGENTE                                    |
//+------------------------------------------------------------------+
void ExecuteRafale(ENUM_ORDER_TYPE type, double atr, int currentPositionsCount) {
   // Trouver le premier panier disponible (1 ou 2)
   int targetBasket = 0;
   if(g_baskets[0].posCount > 0 && g_baskets[1].posCount == 0) targetBasket = 1;
   else if(g_baskets[0].posCount == 0) targetBasket = 0;
   else return; // Les 2 paniers sont pleins

   double effEquity = g_isCentAccount ? (AccountInfoDouble(ACCOUNT_EQUITY) / 100.0) : AccountInfoDouble(ACCOUNT_EQUITY);
   int maxPos = 8;
   if(effEquity < 100.0) maxPos = 3;
   else if(effEquity < 700.0) maxPos = 5;

   int ordersToSend = (targetBasket == 0) ? (maxPos == 3 ? 2 : (maxPos == 5 ? 3 : 5)) : (maxPos - g_baskets[0].posCount);
   if(ordersToSend <= 0) return;

   double baseLot = CalculateBaseLot(atr, type);
   if(baseLot < InpMinLot) return;

   double weights[5] = {0.50, 0.30, 0.20, 0.15, 0.10};
   double totalWeight = 0;
   for(int w = 0; w < ordersToSend; w++) totalWeight += (w < 5) ? weights[w] : 0.10;

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = atr * 1.2;
   double tpDistance = atr * 3.0;

   double sl = (type == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;
   double tp = (type == ORDER_TYPE_BUY) ? price + tpDistance : price - tpDistance;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   string bComment = (targetBasket == 0) ? "JFM_B1" : "JFM_B2";

   for(int i = 0; i < ordersToSend; i++) {
      double lotWeight = (i < 5) ? weights[i] : 0.10;
      double rawLot = baseLot * (lotWeight / totalWeight);
      double positionLot = MathRound(rawLot / step) * step;
      positionLot = MathMax(InpMinLot, MathMin(InpMaxLot, positionLot));

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = _Symbol;
      request.volume       = positionLot;
      request.type         = type;
      request.price        = price;
      request.sl           = NormalizeDouble(sl, _Digits);
      request.tp           = NormalizeDouble(tp, _Digits);
      request.deviation    = 30;
      request.magic        = Magic;
      request.comment      = bComment;

      int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) request.type_filling = ORDER_FILLING_IOC;
      else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) request.type_filling = ORDER_FILLING_FOK;
      else request.type_filling = ORDER_FILLING_RETURN;

      if(!OrderSendAsync(request, result)) {
         PrintFormat("⚠️ Échec envoi asynchrone ordre R%d - Erreur: %d", i + 1, GetLastError());
      }
   }
   g_lastTradeTime = GetTickCount64();
}

//+------------------------------------------------------------------+
//| METRIQUES ARRIÈRE-PLAN (TIMER)                                   |
//+------------------------------------------------------------------+
void UpdateBackgroundMetrics() {
   datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
   double sumPriceVol = 0;
   long sumVol = 0;
   
   int barsToCheck = (int)MathMin(30, Bars(_Symbol, PERIOD_M1));
   for(int i = 0; i < barsToCheck; i++) {
      datetime t = iTime(_Symbol, PERIOD_M1, i);
      if(t < todayStart) break;
      double typical = (iHigh(_Symbol, PERIOD_M1, i) + iLow(_Symbol, PERIOD_M1, i) + iClose(_Symbol, PERIOD_M1, i)) / 3.0;
      long vol = (long)iVolume(_Symbol, PERIOD_M1, i);
      sumPriceVol += typical * vol;
      sumVol += vol;
   }
   g_currentVWAP = (sumVol > 0) ? (sumPriceVol / sumVol) : iClose(_Symbol, PERIOD_M1, 0);

   MqlDateTime dt;
   TimeGMT(dt);
   g_isNewsTime = false;
   if((dt.hour == 13 && dt.min >= 20) || (dt.hour == 14 && dt.min <= 20)) g_isNewsTime = true;
   if(dt.hour == 18) g_isNewsTime = true;
}

//+------------------------------------------------------------------+
//| DASHBOARD PREMIUM : CRÉATION                                     |
//+------------------------------------------------------------------+
void CreateDashboard() {
   int x = InpDashX, y = InpDashY, w = 380, h = 410;
   
   ObjectCreate(0, prefixObj+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_XSIZE, w);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_YSIZE, h);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_BGCOLOR, InpDashBgColor);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_BORDER_COLOR, InpDashBorderColor);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, prefixObj+"BG", OBJPROP_BACK, false);

   ObjectCreate(0, prefixObj+"Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefixObj+"Title", OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, prefixObj+"Title", OBJPROP_YDISTANCE, y + 12);
   ObjectSetString(0, prefixObj+"Title", OBJPROP_TEXT, " JACKPOT FLASH MAN V4.0");
   ObjectSetInteger(0, prefixObj+"Title", OBJPROP_COLOR, InpDashHighlightColor);
   ObjectSetInteger(0, prefixObj+"Title", OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, prefixObj+"Title", OBJPROP_FONT, "Arial Bold");

   string labels[] = {
      "Actif / Magic:", "Type de Compte:", "Équité / Solde:", "Spread (Max):",
      "Positions Actives:", "Profit Panier 1:", "Profit Panier 2:", "Pic Profit (Bouclier):",
      "Cerveau (Régime/Phase):", "Statut News:", "Dernier Trade:",
      "DOM Ratio:", "Rejection Block:", "Anti-Martingale:"
   };
   
   for(int i = 0; i < 14; i++) {
      int ly = y + 45 + (i * 26);
      
      ObjectCreate(0, prefixObj+"L"+IntegerToString(i), OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, prefixObj+"L"+IntegerToString(i), OBJPROP_XDISTANCE, x + 15);
      ObjectSetInteger(0, prefixObj+"L"+IntegerToString(i), OBJPROP_YDISTANCE, ly);
      ObjectSetString(0, prefixObj+"L"+IntegerToString(i), OBJPROP_TEXT, labels[i]);
      ObjectSetInteger(0, prefixObj+"L"+IntegerToString(i), OBJPROP_COLOR, clrSilver);
      ObjectSetInteger(0, prefixObj+"L"+IntegerToString(i), OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, prefixObj+"L"+IntegerToString(i), OBJPROP_FONT, "Arial");

      ObjectCreate(0, prefixObj+"V"+IntegerToString(i), OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, prefixObj+"V"+IntegerToString(i), OBJPROP_XDISTANCE, x + 160);
      ObjectSetInteger(0, prefixObj+"V"+IntegerToString(i), OBJPROP_YDISTANCE, ly);
      ObjectSetString(0, prefixObj+"V"+IntegerToString(i), OBJPROP_TEXT, "...");
      ObjectSetInteger(0, prefixObj+"V"+IntegerToString(i), OBJPROP_COLOR, InpDashTextColor);
      ObjectSetInteger(0, prefixObj+"V"+IntegerToString(i), OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, prefixObj+"V"+IntegerToString(i), OBJPROP_FONT, "Consolas");
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD PREMIUM : MISE À JOUR                                  |
//+------------------------------------------------------------------+
void UpdateDashboard() {
   if(!InpShowDashboard) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   double totalProfit = g_baskets[0].currentProfit + g_baskets[1].currentProfit;
   int totalPos = g_baskets[0].posCount + g_baskets[1].posCount;
   
   string unit = g_isCentAccount ? " c" : " " + currency;
   string eqStr = DoubleToString(equity, 2) + unit + " / " + DoubleToString(balance, 2) + unit;
   
   ObjectSetString(0, prefixObj+"V0", OBJPROP_TEXT, _Symbol + " / " + IntegerToString(Magic));
   ObjectSetString(0, prefixObj+"V1", OBJPROP_TEXT, g_isCentAccount ? "CENT" : "STANDARD");
   ObjectSetString(0, prefixObj+"V2", OBJPROP_TEXT, eqStr);
   
   string spreadStr = IntegerToString(spread) + " / " + DoubleToString(g_maxSpread, 0) + " pts";
   ObjectSetString(0, prefixObj+"V3", OBJPROP_TEXT, spreadStr);
   ObjectSetInteger(0, prefixObj+"V3", OBJPROP_COLOR, (spread <= g_maxSpread) ? clrLime : clrRed);

   ObjectSetString(0, prefixObj+"V4", OBJPROP_TEXT, IntegerToString(totalPos));
   
   ObjectSetString(0, prefixObj+"V5", OBJPROP_TEXT, DoubleToString(g_baskets[0].currentProfit, 2) + unit);
   ObjectSetInteger(0, prefixObj+"V5", OBJPROP_COLOR, (g_baskets[0].currentProfit >= 0) ? clrLime : clrRed);

   ObjectSetString(0, prefixObj+"V6", OBJPROP_TEXT, DoubleToString(g_baskets[1].currentProfit, 2) + unit);
   ObjectSetInteger(0, prefixObj+"V6", OBJPROP_COLOR, (g_baskets[1].currentProfit >= 0) ? clrLime : clrRed);

   double globalPeak = MathMax(g_baskets[0].peakProfit, g_baskets[1].peakProfit);
   ObjectSetString(0, prefixObj+"V7", OBJPROP_TEXT, DoubleToString(globalPeak, 2) + unit);
   ObjectSetInteger(0, prefixObj+"V7", OBJPROP_COLOR, (globalPeak > 0) ? clrGold : clrGray);

   string regimeStr = (g_marketRegime == REGIME_STRICT_BULL) ? "BULL" : (g_marketRegime == REGIME_STRICT_BEAR) ? "BEAR" : "NEUTRE";
   string phaseStr  = (g_candlePhase == PHASE_ACCUMULATION) ? "Accum." : (g_candlePhase == PHASE_IMPULSION) ? "Impuls." : "Distrib.";
   string brainStr  = InpUsePredictiveEngine ? (regimeStr + " / " + phaseStr) : "Désactivé";
   ObjectSetString(0, prefixObj+"V8", OBJPROP_TEXT, brainStr);
   ObjectSetInteger(0, prefixObj+"V8", OBJPROP_COLOR, !InpUsePredictiveEngine ? clrGray : (g_marketRegime != REGIME_NEUTRAL ? clrGold : clrSilver));

   ObjectSetString(0, prefixObj+"V9", OBJPROP_TEXT, g_isNewsTime ? "🚫 BLOQUÉ" : "✅ AUTORISÉ");
   ObjectSetInteger(0, prefixObj+"V9", OBJPROP_COLOR, g_isNewsTime ? clrRed : clrLime);

   ulong timeSinceLastTrade = (GetTickCount64() - g_lastTradeTime) / 1000;
   string lastTradeStr = (g_lastTradeTime == 0) ? "Jamais" : IntegerToString((int)timeSinceLastTrade) + " sec";
   ObjectSetString(0, prefixObj+"V10", OBJPROP_TEXT, lastTradeStr);

   // DOM Ratio
   string domStr = g_useDOMFilter ? (g_domReady ? DoubleToString(g_domRatio, 2) : "attente...") : "Désactivé";
   ObjectSetString(0, prefixObj+"V11", OBJPROP_TEXT, domStr);
   ObjectSetInteger(0, prefixObj+"V11", OBJPROP_COLOR, (g_domReady && g_domRatio > 0.8 && g_domRatio < 1.25) ? clrLime : clrGray);

   // Rejection Block
   string rejStr = "Inactif";
   if(InpUseRejectionBlock) {
      if(g_rejWaiting) {
         ulong elapsed = (GetTickCount64() - g_rejStartTime) / 1000;
         rejStr = "Attente " + IntegerToString((int)elapsed) + "/" + IntegerToString(InpRejectionWaitSec) + "s";
      } else {
         rejStr = "Actif";
      }
   } else {
      rejStr = "Désactivé";
   }
   ObjectSetString(0, prefixObj+"V12", OBJPROP_TEXT, rejStr);
   ObjectSetInteger(0, prefixObj+"V12", OBJPROP_COLOR, g_rejWaiting ? clrYellow : (InpUseRejectionBlock ? clrLime : clrGray));

   // Anti-Martingale
   string amStatus = (g_consecutiveLosses >= InpMaxConsecutiveLosses) ? 
                     ("⚠️ PAUSE (" + IntegerToString(InpPauseAfterLossesMin) + "m)") : 
                     ("✅ OK (" + IntegerToString(g_consecutiveLosses) + "/" + IntegerToString(InpMaxConsecutiveLosses) + ")");
   ObjectSetString(0, prefixObj+"V13", OBJPROP_TEXT, amStatus);
   ObjectSetInteger(0, prefixObj+"V13", OBJPROP_COLOR, g_consecutiveLosses >= InpMaxConsecutiveLosses ? clrRed : clrLime);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| UTILITAIRES                                                      |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         trade.PositionClose(ticket);
      }
   }
}

void ClosePositionsByType(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
            trade.PositionClose(ticket);
         }
      }
   }
}

void CloseAllPositionsInBasket(int basketId) {
   string targetComment = (basketId == 0) ? "JFM_B1" : "JFM_B2";
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), targetComment) >= 0) {
         trade.PositionClose(ticket);
      }
   }
}

int PositionsTotalByMagic() {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
         count++;
      }
   }
   return count;
}

int GetDynamicCooldown(double currentATR) {
   static double avgATR = 0;
   avgATR = (avgATR == 0) ? currentATR : (avgATR * 0.9 + currentATR * 0.1);
   return (currentATR > avgATR * 1.3) ? 2500 : 5000;
}

void CheckConsecutiveLosses() {
   // Si on est déjà en pause, on ne touche à rien
   // La sortie de pause est gérée uniquement dans OnTick
   if(g_consecutiveLosses >= InpMaxConsecutiveLosses) {
      return;
   }
   
   if(HistorySelect(TimeCurrent() - 300, TimeCurrent())) {
      int losses = 0;
      bool foundGain = false;
      
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic) {
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
               if(HistoryDealGetDouble(ticket, DEAL_PROFIT) < 0) {
                  losses++;
               } else {
                  foundGain = true;
                  break; // Un gain interrompt la série
               }
            }
         }
      }
      
      if(foundGain) {
         g_consecutiveLosses = 0;
      } else if(losses > 0) {
         g_consecutiveLosses = losses;
         // On ne fixe g_lastLossTime qu'au moment où on atteint le seuil
         if(g_consecutiveLosses >= InpMaxConsecutiveLosses && g_lastLossTime == 0) {
            g_lastLossTime = TimeCurrent();
         }
      }
   }
}

void InitBaskets() {
   for(int i=0; i<2; i++) {
      g_baskets[i].id = i;
      g_baskets[i].peakProfit = 0;
      g_baskets[i].currentProfit = 0;
      g_baskets[i].posCount = 0;
      g_baskets[i].timeOfPeak = 0;
   }
}
//+------------------------------------------------------------------+
