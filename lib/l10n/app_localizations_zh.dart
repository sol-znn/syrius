// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get notYet => 'Not yet';

  @override
  String get activePillars => 'Active Pillars';

  @override
  String get activeSentinels => 'Active Sentinels';

  @override
  String get address => 'Address';

  @override
  String get addressSearchDescription =>
      'Addresses can be searched by label - \"Address 1\" - and by hex value - \"z1qxemdeddedxt0kenxxxxxxxxxxxxxxxxh9amk0\"';

  @override
  String get addressToCollectRewards =>
      'The address that will be able to collect the Pillar rewards';

  @override
  String get addressToProduceMomentums =>
      'The address that will produce momentums, get it from znn-controller';

  @override
  String get amount => 'Amount';

  @override
  String areYouSureTranfer(Object amount, Object recipient, Object symbol) {
    return 'Are you sure you want to transfer $amount $symbol to $recipient ?';
  }

  @override
  String get asset => 'Asset';

  @override
  String get balance => 'Balance';

  @override
  String get beneficiaryAddress => 'Beneficiary address';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelPlasmaConfirmation =>
      'Are you sure you want to cancel the Plasma fusion?';

  @override
  String get checkPillarStatus => ' to check the Pillar status';

  @override
  String get checkSentinelStatus => ' to check the Sentinel status';

  @override
  String get clickToAddToFavorites => 'Click to add to favorites';

  @override
  String get clickToRemoveFromFavorites => 'Click to remove from favorites';

  @override
  String get coin => 'Coin';

  @override
  String get collect => 'Collect';

  @override
  String get collectPillarRewards => 'Collect Pillar rewards';

  @override
  String get collectSentinelRewards => 'Collect Sentinel rewards';

  @override
  String get collectStakingRewards => 'Collect staking rewards';

  @override
  String get cannotReuseAddressForSentinel =>
      'If this address previously revoked a Sentinel, it cannot create a new Sentinel again. Use a different address before depositing QSR.';

  @override
  String couldNotSend(Object amount, Object recipient, Object symbol) {
    return 'Couldn\'t send $amount $symbol to $recipient';
  }

  @override
  String get burn => 'Burn';

  @override
  String get burnableToken => 'Burnable by any holder';

  @override
  String burnTokenIssueFee(Object amount, Object symbol) {
    return 'You will need to burn $amount $symbol to issue a token';
  }

  @override
  String get continueText => 'Continue';

  @override
  String get create => 'Create';

  @override
  String get createAnotherToken => 'Create another Token';

  @override
  String get createPillarDescription =>
      'Start the process of deploying a Pillar Node in the network';

  @override
  String get createPillarTitle => 'Create Pillar';

  @override
  String get createSentinelDescription =>
      'Start the process of deploying a Sentinel Node in the network';

  @override
  String get createStake => 'create stake';

  @override
  String createStakeDescription(Object kQsrCoinSymbol, Object kZnnCoinSymbol) {
    return 'This card displays information about staking per wallet address. Choose the duration and the amount in $kZnnCoinSymbol for staking in order to receive $kQsrCoinSymbol';
  }

  @override
  String get createStakeTitle => 'Create Stake';

  @override
  String get createToken => 'Create Token';

  @override
  String get createTokenDescription =>
      'Create a token following the ZTS specification';

  @override
  String get createTokenTitle => 'Create Token';

  @override
  String currentAmounts(Object kQsrCoinSymbol, Object kZnnCoinSymbol) {
    return 'This card displays the current $kZnnCoinSymbol and $kQsrCoinSymbol amounts for the selected address';
  }

  @override
  String currentPillarSlotFee(Object coins, Object kQsrCoinSymbol) {
    return 'Current Pillar Slot fee\n$coins $kQsrCoinSymbol';
  }

  @override
  String currentSentinelSlotFee(Object coins, Object kQsrCoinSymbol) {
    return 'Current Sentinel Slot fee\n$coins $kQsrCoinSymbol';
  }

  @override
  String get date => 'Date';

  @override
  String decimals(Object number) {
    return '$number decimals';
  }

  @override
  String get delegateKey => 'DELEGATE';

  @override
  String get delegation => 'Delegation';

  @override
  String delegationPercentageGiven(Object percentage) {
    return 'Delegation percentage given: $percentage';
  }

  @override
  String get delegationReward => 'Delegation reward';

  @override
  String get delegationStats => 'Delegation Stats';

  @override
  String delegationStatsDescription(Object kZnnCoinSymbol) {
    return 'This card displays the amount of $kZnnCoinSymbol and the name of the Pillar that you delegated to';
  }

  @override
  String delegators(Object number) {
    return 'Delegators: $number';
  }

  @override
  String get deposit => 'Deposit';

  @override
  String deposited(Object kQsrCoinSymbol) {
    return '$kQsrCoinSymbol deposited';
  }

  @override
  String depositedCoinWillBurn(Object kQsrCoinSymbol) {
    return 'All the deposited $kQsrCoinSymbol will be burned in order to create the Pillar Slot';
  }

  @override
  String get disassemble => 'DISASSEMBLE';

  @override
  String disassemblePillarToUnlockCoin(Object kZnnCoinSymbol) {
    return 'You will be able to unlock the $kZnnCoinSymbol if you choose to disassemble the Pillar';
  }

  @override
  String disassembleSentinelToUnlockCoin(Object kZnnCoinSymbol) {
    return 'You will be able to unlock the $kZnnCoinSymbol if you choose to disassemble the Sentinel';
  }

  @override
  String get dualCoinStats => 'Dual Coin Stats';

  @override
  String dualCoinStatsDescription(
    Object kQsrCoinSymbol,
    Object kZnnCoinSymbol,
  ) {
    return 'This card displays the circulating $kZnnCoinSymbol and $kQsrCoinSymbol supply from the network';
  }

  @override
  String get duration => 'Duration';

  @override
  String get errorCreatingToken => 'Error while creating a new ZTS token';

  @override
  String errorAddingTokenToFavorites(Object name) {
    return 'Error adding $name token to favorites';
  }

  @override
  String get errorBurningZts => 'Error while trying to burn ZTS';

  @override
  String get errorCollectingPillarRewards =>
      'Error while collecting Pillar rewards';

  @override
  String get errorCollectingSentinelRewards =>
      'Error while collecting Sentinel rewards';

  @override
  String get errorDeployingPillar => 'Error while deploying a Pillar';

  @override
  String get errorDeployingSentinel =>
      'Error while deploying the Sentinel Node';

  @override
  String get errorDisassemblingPillar => 'Error while disassembling Pillar';

  @override
  String get errorDisassemblingSentinel => 'Error while disassembling Sentinel';

  @override
  String get errorCollectingStakingRewards =>
      'Error while collecting staking rewards';

  @override
  String get errorUndelegating => 'Error while undelegating';

  @override
  String get errorUpdatingPillar => 'Error while updating Pillar';

  @override
  String get errorWhileCancellingPlasma => 'Error while cancelling Plasma';

  @override
  String get errorWhileCancellingStake => 'Error while cancelling stake';

  @override
  String get errorGeneratingPlasma => 'Error while generating Plasma';

  @override
  String errorMintingToken(Object symbol) {
    return 'Error while trying to mint $symbol';
  }

  @override
  String errorRemovingTokenFromFavorites(Object name) {
    return 'Error removing $name token from favorites';
  }

  @override
  String get errorTransferringTokenOwnership =>
      'Error while trying to transfer token ownership';

  @override
  String errorWhileDepositing(Object kQsrCoinSymbol) {
    return 'Error while depositing $kQsrCoinSymbol';
  }

  @override
  String get errorWhileGeneratingStake => 'Error while generating stake';

  @override
  String errorWhileWithdrawing(Object kQsrCoinSymbol) {
    return 'Error while withdrawing $kQsrCoinSymbol';
  }

  @override
  String get expiration => 'Expiration';

  @override
  String get expectedProducedMomentums => 'Expected/produced momentums';

  @override
  String get from => 'from';

  @override
  String get fuse => 'Fuse';

  @override
  String fusePlasmaDescription(Object kQsrCoinSymbol) {
    return 'This card displays information about Plasma available per wallet address. A minimum of 10 $kQsrCoinSymbol are needed to be fused in order to generate Plasma. The more $kQsrCoinSymbol fused, the more Plasma is produced for the beneficiary address\n\nInsufficient Plasma: Proof-of-work for Plasma generation; limited to 1 transaction per momentum\nLow Plasma: between 10 and 89 $kQsrCoinSymbol\nAverage Plasma: between 90 and 119 $kQsrCoinSymbol\nHigh Plasma: over 120 $kQsrCoinSymbol; recommended for complex transactions (register Pillars, Sentinels, staking and issuing ZTS tokens)';
  }

  @override
  String get fusePlasmaTitle => 'Fuse Plasma';

  @override
  String fusedPlasmaDescription(Object kQsrCoinSymbol) {
    return 'This card displays all your addresses that have Plasma generated by fusing $kQsrCoinSymbol';
  }

  @override
  String get fusedPlasmaTitle => 'Fused Plasma';

  @override
  String get goBack => 'Go back';

  @override
  String get hAgo => 'h ago';

  @override
  String get hash => 'Hash';

  @override
  String hashValue(Object value) {
    return 'Hash: $value';
  }

  @override
  String get issueToken => 'Issue Token';

  @override
  String get latestTransactionsDescription =>
      'This card displays the latest transactions (including ZTS tokens) of your selected address';

  @override
  String get latestTransactionsTitle => 'Latest Transactions';

  @override
  String get latestTransactionsTransferDescription =>
      'This card displays the latest transactions (including ZTS tokens) involving your wallet addresses';

  @override
  String get level => 'Level';

  @override
  String locked(Object kQsrCoinSymbol) {
    return '$kQsrCoinSymbol locked';
  }

  @override
  String get manageReceivingFunds => 'Manage receiving funds';

  @override
  String get manageSendingFunds => 'Manage sending funds';

  @override
  String management(Object kQsrCoinSymbol) {
    return '$kQsrCoinSymbol management';
  }

  @override
  String get max => 'Max';

  @override
  String get maxSupply => 'Max supply';

  @override
  String get minAgo => 'min ago';

  @override
  String get mint => 'Mint';

  @override
  String get mintable => 'Mintable';

  @override
  String get mintableToken => 'Mintable token';

  @override
  String momentumPercentageGiven(Object percentage) {
    return 'Momentum percentage given: $percentage';
  }

  @override
  String get momentumReward => 'Momentum reward';

  @override
  String get morePlasmaRequired =>
      'More Plasma is required to perform complex transactions. Please fuse enough QSR before proceeding.';

  @override
  String get name => 'Name';

  @override
  String get newOwnerAddress => 'New owner address';

  @override
  String get next => 'Next';

  @override
  String get no => 'no';

  @override
  String get noItemsFound => 'None yet';

  @override
  String get noMoreItems => 'No more items';

  @override
  String get noRewardsCollect => 'No rewards to collect';

  @override
  String get noZtsTokensAvailable => 'No ZTS tokens available';

  @override
  String numberOfDecimals(Object number) {
    return 'Number of decimals: $number';
  }

  @override
  String get ownZtsToken => 'You own this ZTS token';

  @override
  String get password => 'Password';

  @override
  String get pending => 'Pending';

  @override
  String get pendingTransactionsDescription =>
      'This card displays the pending transactions (including ZTS tokens) for the selected address';

  @override
  String get pendingTransactionsTitle => 'Pending Transactions';

  @override
  String get percentageDelegationRewardsGiven =>
      'Percentage of delegation rewards given to the delegators';

  @override
  String get percentageOfMomentumRewards =>
      'Percentage of momentum rewards given to the delegators';

  @override
  String get pillar => 'Pillar';

  @override
  String get pillarCollectDescription =>
      'This card displays your current Pillar rewards (either from your Pillar Node or from your delegation) that are ready to be collected. If there are any rewards available, you will be able to collect them. In order to receive rewards, the Pillar Node needs to be not only registered in the network, but also deployed (use znn-controller for this operation) and it must produce momentums';

  @override
  String get pillarCollectTitle => 'Pillar Collect';

  @override
  String get pillarDelegationError => 'Pillar delegation error';

  @override
  String get pillarDetails => 'Pillar details';

  @override
  String get pillarMomentumAddress => 'Pillar momentum address';

  @override
  String get pillarMomentumRewards => 'Pillar momentum rewards';

  @override
  String get pillarName => 'Pillar name';

  @override
  String get pillarProducerAddress => 'Pillar producer address';

  @override
  String get pillarRegistered => 'Pillar registered';

  @override
  String get pillarRewardAddress => 'Pillar reward address';

  @override
  String get pillarRewardsBlockCreated =>
      'Successfully created block for collecting the pillar rewards. It will take at least 30 seconds for the data to update and to be able to receive the rewards.';

  @override
  String get pillarRewardsDescription =>
      'This card displays a chart with your Pillar rewards. Pillar rewards are generated either by operating a Pillar Node or from delegations to a Pillar Node';

  @override
  String get pillarRewardsTitle => 'Pillar Rewards';

  @override
  String plasmaStatsDescription(Object kQsrCoinSymbol) {
    return 'This card displays information about current Plasma level for each wallet address. Plasma is used as an anti-spam mechanism. More Plasma you have per address, more transactions you will be able to send or receive on that address. Low or insufficient Plasma will require proof-of-work for generation. Fuse 10 $kQsrCoinSymbol or more in order to obtain Plasma for any given address\n\nInsufficient Plasma: Proof-of-work for Plasma generation; limited to 1 transaction per momentum\nLow Plasma: between 10 and 50 $kQsrCoinSymbol\nAverage Plasma: between 50 and 119 $kQsrCoinSymbol\nHigh Plasma: over 120 $kQsrCoinSymbol; recommended to make complex transactions (deploy Pillars, Sentinels, staking and issuing ZTS tokens)';
  }

  @override
  String get plasmaStatsTitle => 'Plasma Stats';

  @override
  String get pillarStats => 'Pillar Stats';

  @override
  String get pillarUpdate => 'Pillar update';

  @override
  String get pillarUpdated => 'Pillar updated';

  @override
  String get pillars => 'Pillars';

  @override
  String pillarsWithNumber(Object number) {
    return 'Pillars: $number';
  }

  @override
  String get pillarsDescription =>
      'This card displays the number of active Pillars in the network';

  @override
  String pillarsListDescription(Object kZnnCoinSymbol) {
    return 'This card displays Pillar Nodes that are currently active in the network. The list contains the name of the Pillar, the associated producer address, the weight (total number of delegations) and your delegation status. You can choose to delegate your $kZnnCoinSymbol balance to any Pillar in order to receive delegation rewards in $kZnnCoinSymbol. You can undelegate the balance at any time, without any penalties. Minimum delegation amount is 1 $kZnnCoinSymbol per address';
  }

  @override
  String get pillarsListTitle => 'Pillars List';

  @override
  String get pillarsTitle => 'Pillars';

  @override
  String get plasma => 'Plasma';

  @override
  String get plasmaCheck => 'Plasma Check';

  @override
  String get pressToReceive => 'Press to receive the transaction';

  @override
  String get producerAddress => 'Producer Address';

  @override
  String quasarTransactions(Object quasar) {
    return '$quasar transactions';
  }

  @override
  String get realtimeStats => 'Realtime Stats';

  @override
  String realtimeStatsDescription(
    Object kQsrCoinSymbol,
    Object kZnnCoinSymbol,
  ) {
    return 'This card displays the number of $kZnnCoinSymbol and $kQsrCoinSymbol transactions. For example, a delegation is considered a $kZnnCoinSymbol transaction from the network\'s perspective. Every interaction with the network embedded contracts is internally considered a transaction';
  }

  @override
  String get receive => 'Receive';

  @override
  String get receiver => 'Receiver';

  @override
  String get recipientAddress => 'Recipient Address';

  @override
  String get register => 'Register';

  @override
  String get registerAnotherPillar => 'Register another Pillar';

  @override
  String get registerPillar => 'Register Pillar';

  @override
  String get registerSentinel => 'Register Sentinel';

  @override
  String get registeredUse => ' registered. Use ';

  @override
  String requiredForPillarSlot(Object coins, Object kQsrCoinSymbol) {
    return '$coins $kQsrCoinSymbol required for a Pillar slot';
  }

  @override
  String requiredForSentinelNode(Object coins, Object kQsrCoinSymbol) {
    return '$coins $kQsrCoinSymbol required for a Sentinel Node';
  }

  @override
  String get revocationWindowOpen => 'Revocation window is open';

  @override
  String get sAgo => 's ago';

  @override
  String get saveQr => 'Save QR';

  @override
  String get searchTokenHint =>
      'Search by name, symbol, owner, or token standard';

  @override
  String get send => 'Send';

  @override
  String get sendTransaction => 'send transaction';

  @override
  String get sentinel => 'Sentinel';

  @override
  String get sender => 'Sender';

  @override
  String get senderAddressDescription =>
      'The address from which the transaction will be sent';

  @override
  String get sent => 'Sent';

  @override
  String sentDetails(
    Object amount,
    Object recipient,
    Object sender,
    Object symbol,
  ) {
    return 'Sent $amount $symbol from $sender to $recipient';
  }

  @override
  String get sentinelAddress => 'Sentinel Address';

  @override
  String get sentinelCollectDescription =>
      'This card displays your current Sentinel rewards that are ready to be collected. If there are any rewards available, you will be able to collect them. In order to receive rewards, the Sentinel Node needs to be not only registered in the network, but also deployed (use znn-controller for this operation) and it must have >90% daily uptime';

  @override
  String get sentinelCollectTitle => 'Sentinel Collect';

  @override
  String get sentinelRewardsDescription =>
      'This card displays a chart with your Sentinel rewards from your Sentinel Node';

  @override
  String get sentinelRewardsBlockCreated =>
      'Successfully created block for collecting the sentinel rewards. It will take at least 30 seconds for the data to update and to be able to receive the rewards.';

  @override
  String get sentinelRewardsTitle => 'Sentinel Rewards';

  @override
  String get sentinelDetectedOnThisAddress =>
      'Sentinel detected on this address';

  @override
  String get sentinelRegistered => 'Sentinel registered';

  @override
  String get sentinelStats => 'Sentinel Stats';

  @override
  String get sentinels => 'Sentinels';

  @override
  String get sentinelsDescription =>
      'This card displays the number of active Sentinels in the network';

  @override
  String get sentinelsListDescription =>
      'This card displays information about the Sentinels that are currently active in the network';

  @override
  String get sentinelsListTitle => 'Sentinels List';

  @override
  String get shareQr => 'Share QR';

  @override
  String get spawn => 'Spawn';

  @override
  String get stake => 'Stake';

  @override
  String get stakeCollectDescription =>
      'This card displays your current staking rewards that are ready to be collected. If there are any rewards available, you will be able to collect them';

  @override
  String get stakeCollectTitle => 'Stake Collect';

  @override
  String get stakingDuration => 'Staking duration';

  @override
  String get stakingStats => 'Staking Stats';

  @override
  String stakingStatsDescription(Object kZnnCoinSymbol) {
    return 'This card displays the number of staking entries and the total $kZnnCoinSymbol that you are currently staking';
  }

  @override
  String get stakesListDescription =>
      'This card displays information about the stake entries for the selected address';

  @override
  String get stakesListTitle => 'Stakes';

  @override
  String get stakingRewardsDescription =>
      'This card displays a chart with your staking rewards from your staking entries';

  @override
  String get stakingRewardsBlockCreated =>
      'Successfully created block for collecting the staking rewards. It will take at least 30 seconds for the data to update and to be able to receive the rewards.';

  @override
  String get stakingRewardsTitle => 'Staking Rewards';

  @override
  String get successfully => 'successfully';

  @override
  String successfullyBurned(Object amount, Object symbol) {
    return 'Successfully burned $amount $symbol';
  }

  @override
  String successfullyBurnedRequestedAmount(
    Object amount,
    Object hash,
    Object symbol,
  ) {
    return 'You have successfully burned the requested amount: $amount $symbol $hash';
  }

  @override
  String successfullyMinted(Object amount, Object symbol) {
    return 'Successfully minted $amount $symbol';
  }

  @override
  String successfullyMintedRequestedAmount(
    Object amount,
    Object hash,
    Object symbol,
  ) {
    return 'You have successfully minted the requested amount: $amount $symbol $hash';
  }

  @override
  String get sufficientPlasma => 'Sufficient Plasma';

  @override
  String get to => 'to';

  @override
  String tokenAddedToFavorites(Object name) {
    return '$name token has been added to favorites';
  }

  @override
  String get tokenBalanceDescription =>
      'This card displays information about ZTS tokens that you currently hold in your wallet';

  @override
  String get tokenBalanceTitle => 'Token Balance';

  @override
  String get tokenBurnTooltip =>
      'When enabled, any holder can burn tokens from their own balance. When disabled, only the token owner can burn.';

  @override
  String get tokenCreation => 'ZNN Check';

  @override
  String get tokenDetails => 'Details';

  @override
  String get tokenDomain => 'Token Domain';

  @override
  String get tokenIssuanceAddressDescription =>
      'This will be your issuance address';

  @override
  String get tokenMetrics => 'Metrics';

  @override
  String get tokenMintableBurnableOptions => 'Mintable and Burnable Options';

  @override
  String tokenMintableBurnableSubtitle(Object burnable, Object mintable) {
    return 'Mintable: $mintable\nBurnable: $burnable';
  }

  @override
  String get tokenMintableTooltip =>
      'Whether or not this token is mintable after creation';

  @override
  String get tokenName => 'Token Name';

  @override
  String tokenRemovedFromFavorites(Object name) {
    return '$name token has been removed from favorites';
  }

  @override
  String get tokenStatusUtilityTooltip =>
      'Token status: utility or non-utility (e.g. security token)';

  @override
  String tokenSummary(Object name, Object symbol, Object tokenStandard) {
    return 'Token $name with symbol $symbol and ZTS $tokenStandard';
  }

  @override
  String tokenSupplyOutOfMax(
    Object maxSupply,
    Object symbol,
    Object totalSupply,
  ) {
    return '$totalSupply out of $maxSupply $symbol';
  }

  @override
  String get tokenSymbol => 'Token Symbol';

  @override
  String get tokenTransactions => 'Token Transactions';

  @override
  String get tokens => 'Tokens';

  @override
  String get tokensCardDescription =>
      'This card displays a grid with all the ZTS tokens from the network, including ZTS tokens issued by you';

  @override
  String get totalSupply => 'Total supply';

  @override
  String get transactionError => 'Error while receiving transaction';

  @override
  String visitDomain(Object domain) {
    return 'Visit $domain';
  }

  @override
  String get transactions => 'Transactions';

  @override
  String get transactionsDescription =>
      'This card displays the total number of transactions settled in the last hour across the network';

  @override
  String get transactionsLastHour => 'transactions in the last hour';

  @override
  String get transfer => 'Transfer';

  @override
  String get transferDescription =>
      'Redirects you to the Transfer tab where you can manage sending and receiving funds';

  @override
  String transferredTokenOwnership(Object name) {
    return 'Successfully transferred ownership of $name token';
  }

  @override
  String transferredTokenOwnershipToAddress(Object address, Object name) {
    return 'Successfully transferred ownership of $name token to address $address';
  }

  @override
  String get transferTokenOwnership => 'Transfer token ownership';

  @override
  String get type => 'Type';

  @override
  String get undelegate => 'UNDELEGATE';

  @override
  String get untilRevocationWindowOpens => 'Until revocation window opens';

  @override
  String get update => 'Update';

  @override
  String get updatePillar => 'Update Pillar';

  @override
  String get updatePillarSettings => 'Update Pillar settings';

  @override
  String get uptime => 'Uptime';

  @override
  String get utilityToken => 'Utility token';

  @override
  String get usDateFormat => 'MM/dd/yyyy';

  @override
  String get viewPillars => 'View Pillars';

  @override
  String get viewMyTokens => 'View my Tokens';

  @override
  String get viewSentinels => 'View Sentinels';

  @override
  String get waitingForDataFetching => 'Waiting for data fetching';

  @override
  String get weight => 'Weight';

  @override
  String get withdraw => 'Withdraw';

  @override
  String get yes => 'yes';

  @override
  String youHaveDeposited(Object coins, Object kQsrCoinSymbol) {
    return 'You have deposited $coins $kQsrCoinSymbol';
  }

  @override
  String zenonTransactions(Object zenon) {
    return '$zenon transactions';
  }

  @override
  String get znnController => 'znn-controller ';

  @override
  String get ztsSearchDescription =>
      'Coins and tokens can be searched by name - \"Zenon\" -, by symbol - \"ZNN\" -, and by token standard - \"zts1znnxxxxxxxxxxxxx9z4ulx\"';

  @override
  String burnTokenConfirm(Object amount) {
    return 'Burn $amount?';
  }

  @override
  String get cannotBeUndone => 'This cannot be undone.';

  @override
  String transferTokenConfirm(Object symbol) {
    return 'Transfer $symbol?';
  }

  @override
  String transferTokenConfirmTo(Object address) {
    return '$address becomes the owner. This cannot be undone.';
  }

  @override
  String get sentinelYours => 'Yours';

  @override
  String disassembleSentinelConfirm(Object address) {
    return 'Disassemble the sentinel of $address?';
  }

  @override
  String get validatorInvalidAddress => 'Invalid address';

  @override
  String get validatorInvalidNode => 'Invalid Node';

  @override
  String get validatorAddressNotInWallet =>
      'Must be an address from your wallet';

  @override
  String validatorFieldEmpty(String fieldName) {
    return '$fieldName must not be empty';
  }

  @override
  String get validatorNumberRequired => 'Number required';

  @override
  String get validatorInvalidNumber => 'Input is not a valid number';

  @override
  String get validatorInvalidAmount => 'Invalid amount';

  @override
  String get validatorError => 'Error';

  @override
  String get validatorValueNull => 'Value is null';

  @override
  String get validatorEmptyBalance => 'Empty balance';

  @override
  String get validatorEnterValidAmount => 'Enter a valid amount';

  @override
  String get validatorTooManyDecimals =>
      'Inputted number has too many decimals';

  @override
  String validatorBalanceBelowMin(String min) {
    return 'Your available balance must be at least $min';
  }

  @override
  String validatorValueMustBe(String value) {
    return 'Value must be $value';
  }

  @override
  String validatorValueMustBeMinAllowed(String value) {
    return 'Value must be  $value';
  }

  @override
  String validatorValueOutOfRange(String min, String max) {
    return 'Value must be between $min and $max';
  }

  @override
  String get validatorValueEmpty => 'Value can\'t be empty';

  @override
  String get validatorEnterAddress => 'Enter an address';

  @override
  String get validatorPasswordsDoNotMatch => 'Passwords do not match';

  @override
  String get validatorPasswordTooWeak => 'Password not strong enough';

  @override
  String get validatorInvalidPassword => 'Invalid password';

  @override
  String get validatorPillarProducerAddressSameSeed =>
      'Pillar producer address must be generated from a different seed';

  @override
  String get validatorMaxSupplyNotZero =>
      'Max supply must be 0 for non-mintable tokens';

  @override
  String get validatorInvalidUrl => 'Invalid URL';

  @override
  String get validatorInvalidHash => 'Invalid hash';

  @override
  String get validatorInvalidSecret => 'Invalid secret';

  @override
  String get ledgerStatusDeny => 'Deny';

  @override
  String get ledgerStatusWrongP1P2 => 'Invalid P1 or P2';

  @override
  String get ledgerStatusWrongDataLength => 'Invalid data length';

  @override
  String get ledgerStatusInactiveDevice => 'Device is inactive';

  @override
  String get ledgerStatusNotAllowed => 'Request not allowed';

  @override
  String get ledgerStatusInsNotSupported =>
      'Instruction not supported, please make sure the Zenon app is opened';

  @override
  String get ledgerStatusClaNotSupported =>
      'Class not supported, please make sure the Zenon app is opened';

  @override
  String get ledgerStatusAppIsNotOpen =>
      'App not open, please open the Zenon app on your device';

  @override
  String get ledgerStatusWrongResponseLength =>
      'Invalid response, please reconnect the device and try again';

  @override
  String get ledgerStatusDisplayBip32PathFail => 'Failed to display BIP32 path';

  @override
  String get ledgerStatusDisplayAddressFail => 'Failed to display address';

  @override
  String get ledgerStatusDisplayAmountFail => 'Failed to display amount';

  @override
  String get ledgerStatusWrongTxLength => 'Invalid transaction length';

  @override
  String get ledgerStatusTxParsingFail => 'Failed to parse transaction';

  @override
  String get ledgerStatusTxHashFail => 'Failed to hash transaction';

  @override
  String get ledgerStatusBadState =>
      'Bad state, please reconnect the device and try again';

  @override
  String get ledgerStatusSignatureFail => 'Failed to create signature';

  @override
  String get ledgerStatusSuccess => 'Success';

  @override
  String get ledgerStatusUnknownError =>
      'Unknown error, please make sure the device is unlocked';

  @override
  String timeAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h ago',
      one: '$count h ago',
    );
    return '$_temp0';
  }

  @override
  String timeAgoMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '$count min ago',
    );
    return '$_temp0';
  }

  @override
  String timeAgoSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count s ago',
      one: '$count s ago',
    );
    return '$_temp0';
  }

  @override
  String durationDaysHours(int days, int hours) {
    return '$days d $hours h';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes m';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes m $seconds s';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get createTokenOpenLabel => 'Create token';

  @override
  String get createTokenHeldLabel => 'Tokens held';

  @override
  String get createTokenFeeLabel => 'Issue fee';

  @override
  String get createTokenDecimalsLabel => 'Decimals';

  @override
  String get createTokenDomainHint => 'example.com';

  @override
  String get plasmaPurposeReceiveTransaction =>
      'Plasma will be generated in order to receive transaction';

  @override
  String get plasmaPurposeSendTransaction =>
      'Plasma will be generated in order to send transaction';

  @override
  String get plasmaPurposeExecuteTransfer =>
      'Plasma will be generated in order to Execute transfer';

  @override
  String plasmaPurposeSendForDapp(String origin) {
    return 'Plasma will be generated in order to Send for $origin';
  }

  @override
  String get plasmaPurposeCreateStake =>
      'Plasma will be generated in order to create stake';

  @override
  String get plasmaPurposeCancelStake =>
      'Plasma will be generated in order to cancel stake';

  @override
  String get plasmaPurposeCollectStakingRewards =>
      'Plasma will be generated in order to Collect staking rewards';

  @override
  String get plasmaPurposeCollectPillarRewards =>
      'Plasma will be generated in order to Collect Pillar rewards';

  @override
  String get plasmaPurposeCollectSentinelRewards =>
      'Plasma will be generated in order to Collect Sentinel rewards';

  @override
  String get plasmaPurposeDelegateToPillar =>
      'Plasma will be generated in order to delegate to Pillar';

  @override
  String get plasmaPurposeUndelegate =>
      'Plasma will be generated in order to undelegate';

  @override
  String plasmaPurposeFuseQsrForPlasma(String qsrSymbol) {
    return 'Plasma will be generated in order to fuse $qsrSymbol for Plasma';
  }

  @override
  String get plasmaPurposeCancelPlasma =>
      'Plasma will be generated in order to cancel Plasma';

  @override
  String get plasmaPurposeRegisterPillar =>
      'Plasma will be generated in order to register Pillar';

  @override
  String get plasmaPurposeUpdatePillar =>
      'Plasma will be generated in order to update pillar';

  @override
  String get plasmaPurposeDisassemblePillar =>
      'Plasma will be generated in order to disassemble Pillar';

  @override
  String plasmaPurposeDepositQsrForPillarSlot(String qsrSymbol) {
    return 'Plasma will be generated in order to deposit $qsrSymbol from Pillar Slot';
  }

  @override
  String plasmaPurposeWithdrawQsrFromPillarSlot(String qsrSymbol) {
    return 'Plasma will be generated in order to withdraw $qsrSymbol from Pillar Slot';
  }

  @override
  String get plasmaPurposeRegisterSentinel =>
      'Plasma will be generated in order to register Sentinel';

  @override
  String get plasmaPurposeDisassembleSentinel =>
      'Plasma will be generated in order to disassemble Sentinel';

  @override
  String plasmaPurposeDepositQsrForSentinelSlot(String qsrSymbol) {
    return 'Plasma will be generated in order to deposit $qsrSymbol for Sentinel Slot';
  }

  @override
  String plasmaPurposeWithdrawQsrFromSentinelSlot(String qsrSymbol) {
    return 'Plasma will be generated in order to withdraw $qsrSymbol from Sentinel Slot';
  }

  @override
  String get plasmaPurposeIssueToken =>
      'Plasma will be generated in order to issue token';

  @override
  String get plasmaPurposeMintToken =>
      'Plasma will be generated in order to mint token';

  @override
  String get plasmaPurposeBurnToken =>
      'Plasma will be generated in order to burn token';

  @override
  String get plasmaPurposeTransferToken =>
      'Plasma will be generated in order to transfer token';

  @override
  String get plasmaPurposeCreateProject =>
      'Plasma will be generated in order to creating project';

  @override
  String get plasmaPurposeCreatePhase =>
      'Plasma will be generated in order to create phase';

  @override
  String get plasmaPurposeUpdatePhase =>
      'Plasma will be generated in order to update phase';

  @override
  String get plasmaPurposeVoteForProject =>
      'Plasma will be generated in order to vote for project';

  @override
  String get plasmaPurposeDonateToAccelerator =>
      'Plasma will be generated in order to donate for accelerator';

  @override
  String get plasmaPurposeStartSwap =>
      'Plasma will be generated in order to start swap';

  @override
  String get plasmaPurposeJoinSwap =>
      'Plasma will be generated in order to join swap';

  @override
  String get plasmaPurposeCompleteSwap =>
      'Plasma will be generated in order to complete swap';

  @override
  String get plasmaPurposeReclaimSwapFunds =>
      'Plasma will be generated in order to reclaim swap funds';

  @override
  String get plasmaNotificationDetails =>
      'Plasma will be generated for this account-block';

  @override
  String notificationErrorWithDetails(String title, Object error) {
    return '$title: $error';
  }

  @override
  String get notificationEmptyTitle => 'Empty title';

  @override
  String get notificationNoDetails => 'No details available';

  @override
  String get nodeUpdatePanelTitle => 'Embedded node';

  @override
  String get nodeUpdateStatusError => 'The node folder could not be read.';

  @override
  String get nodeUpdateLoadedLabel => 'Loaded';

  @override
  String get nodeUpdateNextStartLabel => 'Used at the next start';

  @override
  String get nodeUpdateBundledLabel => 'Bundled';

  @override
  String get nodeUpdateFromFileLabel => 'From a file';

  @override
  String get nodeUpdateMissingLabel => 'No node library found';

  @override
  String get nodeUpdateHashLabel => 'SHA-256';

  @override
  String get nodeUpdateHashCopyTooltip => 'Copy SHA-256';

  @override
  String nodeUpdateReopenStagedLabel(String name) {
    return 'Close and reopen Syrius to use $name.';
  }

  @override
  String get nodeUpdateReopenBundledLabel =>
      'Close and reopen Syrius to use the bundled node.';

  @override
  String get nodeUpdateBadError =>
      'The installed node failed to load. The bundled one is in use.';

  @override
  String get nodeUpdateStagedRejectedError =>
      'The staged node did not match its checksum and was removed.';

  @override
  String get nodeUpdateReleaseLabel => 'Latest release';

  @override
  String get nodeUpdateCheckLabel => 'Check';

  @override
  String get nodeUpdateNotCheckedHint => 'Not checked';

  @override
  String get nodeUpdateNoReleaseLabel => 'This repository has no releases.';

  @override
  String get nodeUpdateCompareUpToDateLabel => 'Up to date';

  @override
  String get nodeUpdateCompareAvailableLabel => 'Update available';

  @override
  String get nodeUpdateCompareStagedLabel => 'Staged for the next start';

  @override
  String get nodeUpdateCompareUnknownLabel => 'Not compared';

  @override
  String get nodeUpdateInstallLabel => 'Install';

  @override
  String get nodeUpdateInstallHint => 'Takes effect at the next start';

  @override
  String get nodeUpdateDownloadLabel => 'Download';

  @override
  String get nodeUpdateFileLabel => 'From file';

  @override
  String nodeUpdateProgressLabel(String received, String total) {
    return '$received of $total MB';
  }

  @override
  String nodeUpdateReadingFileLabel(String name) {
    return 'Reading $name';
  }

  @override
  String get nodeUpdateStagingLabel => 'Installing';

  @override
  String get nodeUpdateInstallTitle => 'Install this node?';

  @override
  String get nodeUpdateRepositoryLabel => 'Repository';

  @override
  String get nodeUpdateTagLabel => 'Release';

  @override
  String get nodeUpdateAssetLabel => 'Asset';

  @override
  String get nodeUpdateFileNameLabel => 'File';

  @override
  String get nodeUpdateNoneLabel => 'None';

  @override
  String get nodeUpdateChecksumFileLabel => 'Checksum file';

  @override
  String get nodeUpdateDigestLabel => 'GitHub digest';

  @override
  String get nodeUpdateChecksumVerifiedLabel =>
      'Matches the release\'s checksum file';

  @override
  String get nodeUpdateChecksumNotListedLabel =>
      'Not listed in the release\'s checksum file';

  @override
  String get nodeUpdateChecksumAbsentLabel =>
      'The release has no checksum file';

  @override
  String get nodeUpdateDigestVerifiedLabel => 'Matches GitHub\'s digest';

  @override
  String get nodeUpdateDigestAbsentLabel =>
      'GitHub gives no digest for this release';

  @override
  String get nodeUpdateFileUncheckedLabel =>
      'Not checked: a file from this computer';

  @override
  String get nodeUpdateInstallConfirm =>
      'This replaces the node that runs inside the wallet. It takes effect at the next start.';

  @override
  String get nodeUpdateUnverifiedTitle => 'Download without verification?';

  @override
  String nodeUpdateUnverifiedConfirm(String tag) {
    return 'Nothing verifies this file. Release $tag publishes no checksum for it.';
  }

  @override
  String get nodeUpdateUnverifiedDownloadLabel => 'Download anyway';

  @override
  String get nodeUpdateRollbackLabel => 'Roll back';

  @override
  String get nodeUpdateRollbackHint => 'Applies at the next start';

  @override
  String get nodeUpdateUseBundledLabel => 'Use bundled node';

  @override
  String get nodeUpdateUsePreviousLabel => 'Use previous';

  @override
  String get nodeUpdateUseBundledTitle => 'Use the bundled node?';

  @override
  String get nodeUpdateUseBundledConfirm =>
      'The nodes listed here are removed. The bundled node runs from the next start.';

  @override
  String get nodeUpdateInstalledLabel => 'Installed';

  @override
  String get nodeUpdateStagedLabel => 'Staged';

  @override
  String get nodeUpdateUsePreviousTitle => 'Use the previous node?';

  @override
  String get nodeUpdateUsePreviousConfirm =>
      'This node replaces the installed one at the next start. Anything staged is removed.';

  @override
  String get nodeUpdateSourceLabel => 'Source repository';

  @override
  String get nodeUpdateSourceHint => 'A GitHub repository, as owner/name';

  @override
  String get nodeUpdateSourceSaveLabel => 'Save';

  @override
  String get nodeUpdateSourceError => 'Enter a repository as owner/name.';

  @override
  String get nodeUpdateSourceForeignHint =>
      'Libraries from another repository are not the Zenon project\'s.';

  @override
  String nodeUpdateRateLimitedUntilError(DateTime time) {
    final intl.DateFormat timeDateFormat = intl.DateFormat.jm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'GitHub is limiting requests from this computer. Try again after $timeString.';
  }

  @override
  String get nodeUpdateRateLimitedError =>
      'GitHub is limiting requests from this computer. Try again later.';

  @override
  String get nodeUpdateNetworkError => 'No connection to GitHub.';

  @override
  String get nodeUpdateNotFoundError =>
      'GitHub has no such repository or file.';

  @override
  String nodeUpdateHttpError(int status) {
    return 'GitHub answered with error $status.';
  }

  @override
  String get nodeUpdateMalformedError => 'GitHub\'s answer could not be read.';

  @override
  String get nodeUpdateForbiddenUrlError =>
      'The download led outside GitHub and was refused.';

  @override
  String nodeUpdateTooLargeError(int megabytes) {
    return 'The file is over $megabytes MB.';
  }

  @override
  String get nodeUpdateSizeMismatchError => 'The download was incomplete.';

  @override
  String get nodeUpdateDigestMismatchError =>
      'The download does not match the published checksum and was deleted.';

  @override
  String get nodeUpdateExpectedLabel => 'Published';

  @override
  String get nodeUpdateActualLabel => 'Downloaded';

  @override
  String get nodeUpdateChecksumConflictError =>
      'The release\'s checksum file and GitHub\'s digest disagree. Nothing was downloaded.';

  @override
  String get nodeUpdateMalformedChecksumsError =>
      'The release\'s checksum file could not be read.';

  @override
  String get nodeUpdateUnverifiedError =>
      'The release publishes no checksum for this file.';

  @override
  String get nodeUpdateNotLibraryError => 'This is not a libznn library.';

  @override
  String get nodeUpdateCancelledError => 'Cancelled.';

  @override
  String nodeUpdateNoAssetError(String tag) {
    return 'Release $tag has no library for this platform.';
  }

  @override
  String get nodeUpdateFileError => 'The file could not be read or written.';

  @override
  String get validatorAmountUsePoint => 'Use a point for decimals';

  @override
  String get nodeSyncingNotificationTitle =>
      'The node is still syncing with the network. Please wait until the loading circle turns green before sending any transactions';

  @override
  String get nodeSyncingNotificationDetails =>
      'The information displayed in the wallet does not reflect the most recent network state. Operations should not be performed, as they will likely become invalid by the time the node is fully synced';

  @override
  String get accountBlockPublishedNotificationTitle =>
      'Account-block published';

  @override
  String accountBlockPublishedNotificationDetails(String blockType) {
    return 'Account-block type: $blockType';
  }

  @override
  String get accountBlockReviewSendNotificationTitle =>
      'Sending transaction, please review the transaction on your hardware device';

  @override
  String get accountBlockReviewReceiveNotificationTitle =>
      'Receiving transaction, please review the transaction on your hardware device';

  @override
  String accountBlockReviewNotificationDetails(String blockType) {
    return 'Review account-block type: $blockType';
  }

  @override
  String get addressAddConfirmNotificationTitle =>
      'Adding address, please confirm the address on your hardware device';

  @override
  String addressAddConfirmNotificationDetails(int index) {
    return 'Confirm address for account index: $index';
  }

  @override
  String addressDefaultLabel(int number) {
    return 'Address $number';
  }

  @override
  String get addressGenerateFailedNotificationTitle =>
      'Error while generating new address';

  @override
  String get embeddedNodeStoppingNotificationTitle =>
      'Waiting for Embedded Node to stop';

  @override
  String get embeddedNodeStoppingNotificationDetails =>
      'The app will close after the Embedded Node has been stopped';

  @override
  String get nodeLocalTimeDiscrepancyError =>
      'Local time discrepancy detected.';

  @override
  String openUrlFailedNotificationTitle(String url) {
    return 'Error while trying to open $url';
  }

  @override
  String openUrlFailedNotificationDetails(String url) {
    return 'Something went wrong while trying to open $url';
  }

  @override
  String get copied => 'Copied';

  @override
  String get clipboardPasteError => 'The clipboard data could not be obtained';

  @override
  String get clipboardPasteFailedNotificationTitle =>
      'Something went wrong while getting the clipboard data';

  @override
  String get walletPasswordIncorrectError => 'Incorrect password';

  @override
  String get walletUnlockFailedNotificationTitle => 'Unlock failed';

  @override
  String walletFileTypeNotSupportedError(String walletType) {
    return 'Wallet type ($walletType) is not supported';
  }

  @override
  String walletFilePathNotFoundError(String path) {
    return 'Given wallet path does not exist ($path)';
  }

  @override
  String get walletFileLedgerNotFoundError =>
      'Cannot find the hardware device, please connect/unlock the device on which the wallet is initialized';

  @override
  String fileDeleteNoFileError(String path) {
    return 'There is no file at the following path: $path';
  }

  @override
  String fileDeleteNoDirectoryError(String path) {
    return 'There is no directory at the following path: $path';
  }

  @override
  String get signMessage32BytesError => 'A 32 byte message is refused. Pad it';

  @override
  String get plasmaLevelHighTooltip => 'High Plasma';

  @override
  String get plasmaLevelAverageTooltip => 'Average Plasma';

  @override
  String get plasmaLevelLowTooltip => 'Low Plasma';

  @override
  String get plasmaLevelInsufficientTooltip => 'Insufficient Plasma';

  @override
  String get autoReceiveFailedNotificationTitle => 'Receive transaction failed';

  @override
  String autoReceiveFailedNotificationDetails(String error) {
    return 'Failed to receive the transaction: $error';
  }

  @override
  String transactionReceivedNotificationTitle(String address) {
    return 'Transaction received on $address';
  }

  @override
  String transactionReceivedNotificationDetails(String hash) {
    return 'Transaction hash: $hash';
  }

  @override
  String get autoUnlockInvalidSwapError => 'Invalid swap';

  @override
  String get autoUnlockAddressNotInWalletError =>
      'Swap address not in default addresses. Please add the address in the addresses list.';

  @override
  String get autoUnlockFailedNotificationTitle => 'Failed to complete swap';

  @override
  String autoUnlockFailedNotificationDetails(String error) {
    return 'Failed to complete the swap: $error';
  }

  @override
  String get completeSwapExpiresTooSoonError =>
      'The swap will expire too soon for a safe swap.';

  @override
  String get completeSwapSecretTooLargeError =>
      'The swap secret size exceeds the maximum allowed size.';

  @override
  String createPillarSuccessMessage(String controller) {
    return 'Pillar registered. Use $controller to check its status.';
  }

  @override
  String get createPillarCollateralLabel => 'Collateral';

  @override
  String get createPillarSlotFeeLabel => 'Slot fee';

  @override
  String get createPillarMomentumShareLabel => 'Momentum share';

  @override
  String get createPillarDelegationShareLabel => 'Delegation share';

  @override
  String get updatePillarRewardsTitle => 'Reward sharing';

  @override
  String get validatorAmountDigitsOnly => 'Digits and a point only';

  @override
  String get validatorAmountWholeNumber => 'Whole QSR only';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonClose => 'Close';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonSeeMore => 'See more';

  @override
  String get commonShowMore => 'Show more';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSave => 'Save';

  @override
  String get commonOk => 'OK';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonSomethingWentWrong => 'Something went wrong';

  @override
  String get commonNotConnectedError => 'Not connected to the network';

  @override
  String get cardAvailableLabel => 'AVAILABLE';

  @override
  String availableBalanceLabel(String amount, String symbol) {
    return '$amount $symbol available';
  }

  @override
  String get nodeNotSyncedError => 'Node is not synced';

  @override
  String get rewardsHistoryLastWeekEmpty => 'No rewards in the last week';

  @override
  String get cardScaffoldAboutTooltip => 'About this card';

  @override
  String get cardScaffoldDescriptionLabel => 'Description';

  @override
  String get cardScaffoldDiscreetModeLabel => 'Discreet mode';

  @override
  String get goToPaletteHint => 'Go to';

  @override
  String get goToPaletteEmpty => 'None yet';

  @override
  String get assetCellUnknownStandardTooltip => 'Unknown token standard';

  @override
  String get receiveQrFailedError => 'Failed to create QR code';

  @override
  String get selectFileHint => 'Drop a file here, or click to browse';

  @override
  String get selectFileInvalidError => 'This file cannot be used';

  @override
  String get selectFileTypeLabel => 'file';

  @override
  String get settingsAddressRenameTooltip => 'Rename';

  @override
  String get settingsAddressLabelHint => 'Label';

  @override
  String get settingsAddressLabelEmptyError => 'Label can\'t be empty';

  @override
  String settingsAddressLabelTooLongNotificationTitle(int max) {
    String _temp0 = intl.Intl.pluralLogic(
      max,
      locale: localeName,
      other: 'The label has more than $max characters',
      one: 'The label has more than $max character',
    );
    return '$_temp0';
  }

  @override
  String settingsAddressLabelTooLongNotificationDetails(
    String label,
    int length,
    int max,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other:
          'The label $label is $length characters long, which is more than the $max limit.',
      one:
          'The label $label is $length character long, which is more than the $max limit.',
    );
    return '$_temp0';
  }

  @override
  String get settingsAddressLabelExistsNotificationTitle =>
      'Label already exists';

  @override
  String settingsAddressLabelExistsNotificationDetails(String label) {
    return 'Label $label already exists in the database';
  }

  @override
  String get settingsAddressRenameFailedNotificationTitle =>
      'Something went wrong while changing the address label';

  @override
  String settingsNodeChainIdTooltip(int client, int node) {
    return 'Client chain identifier: $client\nNode chain identifier: $node';
  }

  @override
  String settingsNodeChainIdMismatchTooltip(int client, int node) {
    return 'Chain identifier mismatch\nClient chain identifier: $client\nNode chain identifier: $node';
  }

  @override
  String get settingsNodeEncryptedTooltip => 'Encrypted connection';

  @override
  String get settingsNodeUnencryptedTooltip => 'Unencrypted connection';

  @override
  String get settingsNodeEmbeddedTooltip =>
      'Integrated Full Node: enhanced security and privacy';

  @override
  String get settingsNodeEmbeddedSyncTooltip =>
      'The Embedded Node validates all network transactions\nIt may take several hours to fully sync with the network';

  @override
  String get settingsNodeCommunityTooltip => 'Community Node';

  @override
  String get settingsNodeEditTooltip => 'Edit node';

  @override
  String get settingsNodeDeleteLabel => 'Delete node';

  @override
  String settingsNodeDeleteConfirm(String node) {
    return 'Delete $node from the list of nodes? This can\'t be undone.';
  }

  @override
  String get settingsNodeAddressHint => 'Node address with port';

  @override
  String get settingsNodeEmptyError => 'Node address can\'t be empty';

  @override
  String settingsNodeTooLongError(int max) {
    String _temp0 = intl.Intl.pluralLogic(
      max,
      locale: localeName,
      other: 'The node has more than $max characters',
      one: 'The node has more than $max character',
    );
    return '$_temp0';
  }

  @override
  String get settingsNodeExistsError => 'Node already exists';

  @override
  String settingsNodeDeleteFailedNotificationTitle(String node) {
    return 'Error during deleting node $node from the database';
  }

  @override
  String seedChoiceWordsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '$count word',
    );
    return '$_temp0';
  }

  @override
  String durationDays(int days) {
    return '$days d';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationDaysClock(int days, String clock) {
    return '$days d $clock';
  }

  @override
  String acceleratorClosesIn(String duration) {
    return 'Closes in $duration';
  }

  @override
  String cancelUnlocksIn(String duration) {
    return 'Unlocks in $duration';
  }

  @override
  String p2pSwapExpiresIn(String duration) {
    return 'The swap expires in $duration';
  }

  @override
  String stakeDurationMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '$count month',
    );
    return '$_temp0';
  }

  @override
  String createSentinelSuccessMessage(String controller) {
    return 'Sentinel registered. Use $controller to check its status.';
  }

  @override
  String get createSentinelDepositLabel => 'Deposit';

  @override
  String get railExpand => 'Expand';

  @override
  String get railCollapse => 'Collapse';

  @override
  String get stripGeneratingPlasma => 'Generating plasma';

  @override
  String get stripPlasmaIdle => 'Plasma idle';

  @override
  String stripSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String stripPlasmaTypical(int seconds) {
    return 'usually about $seconds s';
  }

  @override
  String stripSending(String amount) {
    return 'Sending $amount';
  }

  @override
  String stripSendingMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sending $count blocks',
      one: 'Sending 1 block',
    );
    return '$_temp0';
  }

  @override
  String get stripWaitingMomentum => 'waiting for a momentum';

  @override
  String stripMomentumsBehind(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString momentums behind',
      one: '1 momentum behind',
    );
    return '$_temp0';
  }

  @override
  String get stripPeers => 'Peers';

  @override
  String get stakingStaked => 'Staked';

  @override
  String get stakingToCollect => 'To collect';

  @override
  String get stakingLast7Days => 'Last 7 days';

  @override
  String get stakingChart => 'Rewards';

  @override
  String get plasmaPageFusedByYou => 'Fused by you';

  @override
  String get plasmaPageFused => 'Fused';

  @override
  String get plasmaPageOtherAddresses => 'Other addresses';

  @override
  String plasmaPageLowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count low',
      one: '1 low',
    );
    return '$_temp0';
  }

  @override
  String plasmaPageCancelFuses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cancel $count fuses',
      one: 'Cancel 1 fuse',
    );
    return '$_temp0';
  }

  @override
  String plasmaPageCancelFusesConfirm(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cancel $count fuses, $amount in all?',
      one: 'Cancel 1 fuse of $amount?',
    );
    return '$_temp0';
  }

  @override
  String plasmaPageCancelFusesDone(int done, int total) {
    return '$done of $total submitted';
  }

  @override
  String get railHome => 'Home';

  @override
  String get railStaking => 'Staking';

  @override
  String get railNodes => 'Nodes';

  @override
  String get railSwap => 'Swap';

  @override
  String get railAccelerator => 'Accelerator';

  @override
  String get railNotifications => 'Notifications';

  @override
  String get railSettings => 'Settings';

  @override
  String get railLock => 'Lock';

  @override
  String get railLocked => 'Locked';

  @override
  String get railUnseen => 'Unseen';

  @override
  String get settingsSectionAddresses => 'Addresses';

  @override
  String get settingsSectionNode => 'Node';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsSectionDisplay => 'Display';

  @override
  String get settingsSectionWallet => 'Wallet';

  @override
  String get settingsSectionApps => 'Apps';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get stakingStarted => 'Started';

  @override
  String get stakingUnlocks => 'Unlocks';

  @override
  String get stakingUnlocked => 'Unlocked';

  @override
  String get stakingCancelWithdraw => 'Cancel and withdraw';

  @override
  String get stakingNewStake => 'New stake';

  @override
  String stakingStakeAmount(String amount) {
    return 'Stake $amount ZNN';
  }

  @override
  String stakingAmountOf(String amount) {
    return 'of $amount ZNN';
  }

  @override
  String stakingStartedDaysAgo(int count) {
    return '$count d ago';
  }

  @override
  String stakingStartedMonthsAgo(int count) {
    return '$count mo ago';
  }

  @override
  String stakingUnlockMonthsDays(int months, int days) {
    return '$months mo $days d';
  }

  @override
  String get displayTheme => 'Theme';

  @override
  String get displayTextSize => 'Text size';

  @override
  String get displayLanguage => 'Language';

  @override
  String get displayMenu => 'Menu';

  @override
  String get displayMenuHint => 'Icons only, labels on hover';

  @override
  String get displayIcons => 'Icons';

  @override
  String get displayLabels => 'Labels';

  @override
  String get displayHideBalances => 'Hide balances';

  @override
  String get displayHideBalancesHint => 'Also the eye on Home';

  @override
  String get displayDollarValues => 'Dollar values';

  @override
  String get displayDollarValuesHint =>
      'ZNN and QSR at CoinGecko\'s price, asked once a minute while a value is on screen. Mainnet\'s price on every chain.';

  @override
  String get displayExplorer => 'Explorer';

  @override
  String get displayExplorerHint => 'Links follow the chain. None off chain 1.';

  @override
  String get displaySystem => 'System';

  @override
  String get displayDark => 'Dark';

  @override
  String get displayLight => 'Light';

  @override
  String get displaySmall => 'Small';

  @override
  String get displayDefault => 'Default';

  @override
  String get displayLarge => 'Large';

  @override
  String get displayHuge => 'Huge';

  @override
  String displaySaveFailed(String setting) {
    return 'Could not save $setting';
  }

  @override
  String get transferZap => 'Zap';

  @override
  String get transferToReceive => 'To receive';

  @override
  String get transferReceiving => 'Receiving';

  @override
  String get transferAutoReceiveOn => 'Auto-receive on';

  @override
  String get transferAutoReceiveOff => 'Auto-receive off';

  @override
  String get nodesDelegatedTo => 'Delegated to';

  @override
  String get nodesWeight => 'weight';

  @override
  String get nodesChange => 'Change';

  @override
  String get nodesDelegate => 'Delegate';

  @override
  String get nodesUndelegate => 'Undelegate';

  @override
  String get nodesRewards => 'Rewards';

  @override
  String get nodesMore => 'More';

  @override
  String get nodesYourPillar => 'Your pillar';

  @override
  String get nodesYourSentinel => 'Your sentinel';

  @override
  String get nodesToCollect => 'To collect';

  @override
  String get nodesNoneYet => 'None yet';

  @override
  String get stripNode => 'Node';

  @override
  String get stripChain => 'Chain';

  @override
  String stripMomentumHeight(int height) {
    return 'Momentum height: $height';
  }

  @override
  String get stripDisconnected => 'Disconnected';

  @override
  String get stripConnecting => 'Connecting';

  @override
  String get stripSynced => 'Connected and in sync';

  @override
  String stripSyncing(int current, int target) {
    return 'Syncing, momentum $current of $target';
  }

  @override
  String get stripWaitingConfirmation => 'Waiting for a momentum';

  @override
  String stripSecondsAtLeast(int seconds) {
    return '≥$seconds s';
  }

  @override
  String nodesUndelegateConfirm(String pillarName) {
    return 'Undelegate from $pillarName?';
  }

  @override
  String get homeCopyAddress => 'Copy address';

  @override
  String get homeSwitchAddress => 'Switch address';

  @override
  String get homeShowBalances => 'Show balances';

  @override
  String get homeLoading => 'Loading';

  @override
  String get homeNodeNotAnswering => 'Node not answering';

  @override
  String get homePlasmaHigh => 'High';

  @override
  String get homePlasmaMedium => 'Medium';

  @override
  String get homePlasmaLow => 'Low';

  @override
  String get homePlasmaNone => 'None';

  @override
  String get homeToCollect => 'To collect';

  @override
  String get homeCollectAll => 'Collect all';

  @override
  String get homeNoneYet => 'None yet';

  @override
  String get homePending => 'Pending';

  @override
  String get homePendingMomentum => 'momentum';

  @override
  String get homeAmountUnknown => 'Unknown';

  @override
  String get homeCollectionUncertain => 'Collection outcome unknown';

  @override
  String get homePlasmaNeedsWork => 'Sends need proof of work';

  @override
  String homePlasmaSends(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Enough for about $count sends',
      one: 'Enough for 1 send',
    );
    return '$_temp0';
  }

  @override
  String get bellNeedsYou => 'Needs you';

  @override
  String get bellToday => 'Today';

  @override
  String get bellYesterday => 'Yesterday';

  @override
  String get bellClear => 'Clear';

  @override
  String get bellNoneYet => 'None yet';

  @override
  String get bellApprove => 'Approve';

  @override
  String get bellDecline => 'Decline';

  @override
  String get bellRemove => 'Remove';

  @override
  String get bellRequested => 'Requested';

  @override
  String get bellRequired => 'Required';

  @override
  String get bellOptional => 'Optional';

  @override
  String get bellApproved => 'To approve';

  @override
  String get bellAccounts => 'Accounts';

  @override
  String get bellChains => 'Chains';

  @override
  String get bellMethods => 'Methods';

  @override
  String get bellEvents => 'Events';

  @override
  String get bellUnavailable => 'Request unavailable';

  @override
  String get bellApprovalFailed => 'Connection failed. Check Apps.';

  @override
  String get bellHistoryFailed => 'Notifications unavailable';

  @override
  String get bellExpand => 'Show events';

  @override
  String get bellCollapse => 'Hide events';

  @override
  String get bellBlockPublished => 'Block published';

  @override
  String bellFoldCount(int count) {
    return '× $count';
  }

  @override
  String get bellConnectRequest => 'Asks to connect.';

  @override
  String get bellResolving => 'Waiting';

  @override
  String get bellNow => 'now';

  @override
  String bellMinutesAgo(int count) {
    return '$count min';
  }

  @override
  String bellHoursAgo(int count) {
    return '$count h';
  }

  @override
  String bellDaysAgo(int count) {
    return '$count d';
  }

  @override
  String get goToPalettePages => 'Pages';

  @override
  String get goToPaletteActions => 'Actions';

  @override
  String get goToPaletteAddresses => 'Addresses';

  @override
  String get goToPaletteMove => 'move';

  @override
  String get goToPaletteOpen => 'open';

  @override
  String goToPaletteShortcuts(
    String first,
    String last,
    String lock,
    String refresh,
  ) {
    return '$first to $last pages · $lock lock · $refresh refresh';
  }

  @override
  String goToPaletteSendTo(String name) {
    return 'Send to $name';
  }

  @override
  String get goToPaletteDelegate => 'Delegation';

  @override
  String get goToPaletteDeleteCache => 'Delete cache';

  @override
  String get goToPaletteDelegateAction => 'Delegate to a pillar';

  @override
  String get goToPaletteSendToHint => 'Send to';

  @override
  String get goToPaletteDeleteCacheConfirm =>
      'Delete cached data and close Syrius?';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get publicationSessionChanged =>
      'Wallet or node changed. Review and try again.';

  @override
  String get stripWalletUpdates => 'Wallet updates';

  @override
  String stripUpdateAvailable(String version) {
    return 'Syrius $version is out';
  }

  @override
  String get activityTitle => 'Activity';

  @override
  String get activityReceived => 'Received';

  @override
  String get activityDelegated => 'Delegated';

  @override
  String get activityFused => 'Fused';

  @override
  String get activityReward => 'Reward';

  @override
  String get activityStaked => 'Staked';

  @override
  String get activityMessage => 'Message';

  @override
  String get activityNow => 'Now';

  @override
  String activityMinutes(int count) {
    return '$count min';
  }

  @override
  String activityHours(int count) {
    return '$count h';
  }

  @override
  String activityDays(int count) {
    return '$count d';
  }

  @override
  String get activityUnitsUnavailable => 'Units unavailable';

  @override
  String get activityExplorer => 'Open in explorer';

  @override
  String get activitySelectedAddress => 'Selected address';

  @override
  String get activityUnavailable => 'Activity unavailable';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get lockOpening => 'Opening the wallet';

  @override
  String get lockAddWallet => 'Add a wallet';

  @override
  String get lockForgotPassword => 'Forgot the password';

  @override
  String get lockShowPassword => 'Show password';

  @override
  String get lockHidePassword => 'Hide password';

  @override
  String get lockAttemptSaveFailed =>
      'Unlock state was not saved. Restart Syrius.';

  @override
  String lockTriesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tries left. The wallet resets at the limit.',
      one: '1 try left. The wallet resets at the limit.',
    );
    return '$_temp0';
  }

  @override
  String get sendRecent => 'Recent';

  @override
  String get sendAddressBook => 'Address book';

  @override
  String get sendSearchContacts => 'Search contacts';

  @override
  String get sendClearRecipient => 'Clear recipient';

  @override
  String get sendAvailable => 'Available';

  @override
  String get sendEnterAddress => 'Enter an address';

  @override
  String get sendEnterAmount => 'Enter an amount';

  @override
  String sendNotEnough(String symbol) {
    return 'Not enough $symbol';
  }

  @override
  String sendAmount(String amount, String symbol) {
    return 'Send $amount $symbol';
  }

  @override
  String get sendWaitingForNode => 'Waiting for the node';

  @override
  String get sendCheckAddress => 'Check the full address';

  @override
  String sendLooksLike(String name) {
    return 'Looks like $name';
  }

  @override
  String get sendLookAlikeDetail =>
      'The ends match a known address. Check the full address.';

  @override
  String get sendKnownAddress => 'Known address';

  @override
  String get sendTypedAddress => 'Typed address';

  @override
  String sendUseKnown(String name) {
    return 'Use $name';
  }

  @override
  String get sendUseTypedAnyway => 'Use typed address';

  @override
  String get sendFirstTimeRecipient => 'First send recorded here';

  @override
  String sendLastSent(String name, String time) {
    return '$name · Last sent $time';
  }

  @override
  String sendNodeBehind(int count) {
    return 'Node is $count momentums behind';
  }

  @override
  String get sendWaitForSync => 'Wait for sync';

  @override
  String get sendContactsUnavailable =>
      'Address book unavailable. Check the full address.';

  @override
  String sendConfirmTitle(String amount, String symbol) {
    return 'Send $amount $symbol?';
  }

  @override
  String get sendConfirmTo => 'To';

  @override
  String get sendConfirmFrom => 'From';

  @override
  String get sendPlasmaPending => 'Checked when sending';

  @override
  String get sendHardwareConfirm => 'Confirm on your device after Send.';

  @override
  String get sendOutcomeUnavailable => 'Send outcome unavailable';

  @override
  String get sendOutcomeUncertain => 'Check Activity before sending again.';

  @override
  String get receiveCopyAddress => 'Copy address';

  @override
  String get receiveShowQr => 'Show QR';

  @override
  String get receiveHideQr => 'Hide QR';

  @override
  String get receiveRequestAmount => 'Request an amount';

  @override
  String get receiveShareImage => 'Share image';

  @override
  String get receiveInvalidAmount =>
      'Enter a positive amount within this token\'s precision';

  @override
  String get receiveExportFailed => 'The QR image could not be exported';

  @override
  String get receiveCopyFailed => 'Could not copy address. Try again.';

  @override
  String get zapRandomAlien => 'A random alien';

  @override
  String get zapCandidatesUnavailable => 'Recipients unavailable';

  @override
  String get zapPickAnother => 'Pick another';

  @override
  String get zapCopyRecipient => 'Copy recipient';

  @override
  String get zapDefaultMessage => 'You got zapped. Have a great day, alien.';

  @override
  String zapBytes(int used) {
    return '$used/140';
  }

  @override
  String get zapMessageTooLong => 'Use at most 140 bytes';

  @override
  String get zapOneBlock => 'One block';

  @override
  String get zapTwoBlocks => 'Two blocks, one per coin';

  @override
  String get zapBlockPerCoin => 'One block per coin';

  @override
  String get zapNodeNotice =>
      'Your node can steer the pick. A hardware wallet confirms each block.';

  @override
  String zapAmountLabel(String symbol) {
    return '$symbol amount';
  }

  @override
  String zapActionBoth(String znn, String qsr) {
    return 'Zap $znn ZNN + $qsr QSR';
  }

  @override
  String zapActionSingle(String amount, String symbol) {
    return 'Zap $amount $symbol';
  }

  @override
  String get pillarsSearchLoaded => 'Search loaded rows';

  @override
  String get pillarsSortLoaded => 'Sort loaded rows';

  @override
  String get pillarsLoadMore => 'Load more';

  @override
  String get pillarsNoMatches => 'No matches';

  @override
  String get pillarsShares => 'Shares';

  @override
  String get pillarsAprEstimate => 'APR est.';

  @override
  String get pillarsSortProduction => 'Uptime';

  @override
  String get pillarsYours => 'Yours';

  @override
  String get pillarsDelegated => 'Delegated';

  @override
  String get pillarsReward => 'Reward';

  @override
  String get pillarsRegistered => 'Registered';

  @override
  String get pillarsUnavailable => 'Unavailable';

  @override
  String get pillarsMomentums => 'Momentums';

  @override
  String pillarsMomentumsValue(String produced, String expected) {
    return '$produced of $expected expected';
  }

  @override
  String get pillarOwnerLocked => 'Locked';

  @override
  String get pillarOwnerDeposited => 'Deposited';

  @override
  String get pillarOwnerSlotCost => 'Registration cost';

  @override
  String get pillarOwnerProducer => 'Producer';

  @override
  String get pillarOwnerReward => 'Reward';

  @override
  String get pillarOwnerRevocable => 'Revocable';

  @override
  String get pillarOwnerSharing => 'Sharing';

  @override
  String get pillarOwnerMomentums => 'Momentums';

  @override
  String pillarOwnerShares(int momentum, int delegate) {
    return '$momentum% block · $delegate% delegate';
  }

  @override
  String pillarOwnerProduction(int produced, int expected) {
    return '$produced of $expected';
  }

  @override
  String get pillarOwnerDepositQsr => 'Deposit QSR';

  @override
  String get pillarOwnerWithdrawQsr => 'Withdraw QSR';

  @override
  String get pillarOwnerDisassemble => 'Disassemble';

  @override
  String get pillarOwnerUnavailable => 'Unavailable';

  @override
  String pillarOwnerRevokeQuestion(String name) {
    return 'Disassemble $name?';
  }

  @override
  String get pillarOwnerRevokeFinalTitle => 'Confirm disassembly';

  @override
  String pillarOwnerRevokeConsequence(String name) {
    return 'This removes $name as a pillar.';
  }

  @override
  String get nodesOwner => 'Owner';

  @override
  String get nodesRegistered => 'Registered';

  @override
  String get nodesRevocable => 'Revocable';

  @override
  String get nodesStatus => 'Status';

  @override
  String get nodesActive => 'Active';

  @override
  String get nodesRevoked => 'Revoked';

  @override
  String get nodesNow => 'now';

  @override
  String nodesInDuration(String duration) {
    return 'in $duration';
  }

  @override
  String nodesAgoDuration(String duration) {
    return '$duration ago';
  }

  @override
  String durationMonths(int months) {
    return '$months mo';
  }

  @override
  String durationYears(int years) {
    return '$years y';
  }

  @override
  String get nodesUnavailable => 'Unavailable';

  @override
  String sentinelOwnerRevokeConsequence(String address) {
    return 'This removes the sentinel of $address.';
  }

  @override
  String get tokensHeld => 'Held';

  @override
  String get tokensFavorites => 'Favorites';

  @override
  String get tokensAll => 'All';

  @override
  String get tokensYouHold => 'You hold';

  @override
  String get tokensIssuedByYou => 'Issued by you';

  @override
  String get tokensSearchHint => 'Name, symbol, owner or ZTS';

  @override
  String get tokensBalanceUnavailable => 'Balance unavailable';

  @override
  String get tokensCatalogUnavailable => 'Tokens unavailable';

  @override
  String get tokensSearchClear => 'Clear';

  @override
  String get tokensSupply => 'Supply';

  @override
  String get tokensOwner => 'Owner';

  @override
  String get tokensToken => 'Token';

  @override
  String plasmaPageEntries(int count) {
    return 'in $count entries';
  }

  @override
  String plasmaPageSelected(int count) {
    return '$count selected';
  }

  @override
  String get plasmaPageSelectHint => 'Select rows to cancel together';

  @override
  String get plasmaPageCancelable => 'Cancelable';

  @override
  String get plasmaPageSubmitted => 'Submitted';

  @override
  String get plasmaPageSubmitting => 'Submitting';

  @override
  String get plasmaPageUnknown => 'Unknown';

  @override
  String get plasmaPageCopyFusion => 'Copy fusion hash';

  @override
  String get registrationWaiting => 'Waiting for confirmation';

  @override
  String registrationPillarRegistered(String name) {
    return '$name is registered';
  }

  @override
  String get registrationPillarReady =>
      'It joins the producers within a few momentums.';

  @override
  String get registrationTokenCreated => 'Token created';

  @override
  String get registrationViewPillar => 'View pillar';

  @override
  String get registrationViewSentinel => 'View sentinel';

  @override
  String get registrationViewToken => 'View token';

  @override
  String get registrationDone => 'Done';

  @override
  String get registrationBlock => 'Block';

  @override
  String get registrationChain => 'Chain';

  @override
  String get launchSkipHint => 'Click or press a key to skip';

  @override
  String get plasmaFuseFor => 'For';

  @override
  String get plasmaFuseAnotherAddress => 'Another address';

  @override
  String plasmaFuseAction(String amount) {
    return 'Fuse $amount QSR';
  }

  @override
  String get plasmaFuseLockNote => 'Cancel unlocked fuses to recover QSR.';

  @override
  String get tokensFlags => 'Flags';

  @override
  String get tokensTransferOwnership => 'Transfer ownership';

  @override
  String get tokensDomain => 'Domain';

  @override
  String get tokensUtility => 'Utility';

  @override
  String get tokensMintableByOwner => 'Yes, by owner';

  @override
  String get tokensBurnableByHolder => 'By any holder';

  @override
  String get tokensBurnableByOwner => 'By owner';

  @override
  String get tokensYes => 'Yes';

  @override
  String get tokensNo => 'No';

  @override
  String get tokensThisAddress => 'This address';

  @override
  String get tokensCopyStandard => 'Copy token standard';

  @override
  String get tokensCopyOwner => 'Copy owner address';

  @override
  String tokensRemainingSupply(String amount) {
    return '$amount left under the max supply.';
  }

  @override
  String get tokensTransferNote => 'Only the new owner can give it back.';

  @override
  String get tokensActionUnavailable => 'Unavailable';

  @override
  String get tokensActionSubmitting => 'Submitting';

  @override
  String get tokensActionSubmitted => 'Submitted';

  @override
  String get tokensActionUnknown => 'Unknown';

  @override
  String get tokenCreateNameAndSymbol => 'Name and symbol';

  @override
  String get tokenCreateOptions => 'Options';

  @override
  String get tokenCreateIssue => 'Issue';

  @override
  String get tokenCreateFee => 'Fee';

  @override
  String get tokenCreateHave => 'Have';

  @override
  String get tokenCreatePreview => 'Preview';

  @override
  String get tokenCreateBurned => 'burned';

  @override
  String get tokenCreateSymbol => 'Symbol';

  @override
  String get tokenCreateDomain => 'Domain';

  @override
  String get tokenCreateDomainNote => 'Optional. Where the token is described.';

  @override
  String get tokenCreateBack => 'Back';

  @override
  String get tokenCreateReviewSupply => 'Review supply';

  @override
  String get tokensBurnable => 'Burnable';

  @override
  String get tokensAnotherAction => 'Another';

  @override
  String get plasmaFuseAnotherAction => 'Another';

  @override
  String get nodeSettingsTitle => 'Nodes';

  @override
  String get nodeSettingsAdd => 'Add node';

  @override
  String get nodeSettingsEmbedded => 'Embedded node';

  @override
  String get nodeSettingsConnected => 'Connected';

  @override
  String get nodeSettingsUnknown => 'Not checked';

  @override
  String get nodeSettingsChainTitle => 'Chain identifier';

  @override
  String nodeSettingsClientChain(int chain) {
    return 'Client chain $chain';
  }

  @override
  String nodeSettingsNodeChain(int chain) {
    return 'Chain $chain';
  }

  @override
  String get nodeSettingsMomentum => 'Momentum';

  @override
  String get nodeSettingsPeers => 'Peers';

  @override
  String get nodeSettingsPeerIp => 'IP';

  @override
  String get nodeSettingsPeerKey => 'Public key';

  @override
  String get nodeSettingsNone => 'None yet';

  @override
  String get nodeSettingsSporks => 'Sporks';

  @override
  String get nodeSettingsSporksMode => 'Sporks mode';

  @override
  String get nodeSettingsMismatchTitle => 'Chain identifier mismatch';

  @override
  String nodeSettingsMismatchBody(int nodeChain, int clientChain) {
    return 'Node chain $nodeChain. Client chain $clientChain. Proceed?';
  }

  @override
  String get nodeSettingsProceed => 'Proceed anyway';

  @override
  String get nodeSettingsChanged => 'Node connected';

  @override
  String get nodeSettingsAdded => 'Node added';

  @override
  String get nodeSettingsUpdated => 'Node saved';

  @override
  String get nodeSettingsDeleted => 'Node deleted';

  @override
  String get nodeSettingsChainChanged => 'Chain changed';

  @override
  String get nodeSettingsFailed => 'Node change failed. Try again.';

  @override
  String get nodeSettingsSaveFailed => 'Could not save. Try again.';

  @override
  String get nodeSettingsSessionChanged => 'Session changed. Try again.';

  @override
  String get nodeSettingsChainHint => 'Used to sign transactions';

  @override
  String get nodeSettingsChainInvalid => 'Enter a positive whole number';

  @override
  String get nodeSettingsUpdating => 'Connecting';

  @override
  String get nodeSettingsDeleteQuestion => 'Delete this node?';

  @override
  String get nodeSettingsSynced => 'Synced';

  @override
  String get nodeSettingsSyncing => 'Syncing';

  @override
  String get securitySettingsLockAfter => 'Lock after';

  @override
  String get securitySettingsInactivity => 'Of inactivity';

  @override
  String securitySettingsMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get securitySettingsHour => '1 h';

  @override
  String get securitySettingsOnClose => 'On close';

  @override
  String securitySettingsBiometricUnlock(String method) {
    return 'Unlock with $method';
  }

  @override
  String get securitySettingsWindowsHello => 'Windows Hello';

  @override
  String get securitySettingsTouchId => 'Touch ID';

  @override
  String get securitySettingsBiometricHint =>
      'The password still works. Later.';

  @override
  String get securitySettingsWrongPasswordLimit =>
      'Remove this wallet after wrong passwords';

  @override
  String get securitySettingsWrongPasswordHint =>
      'On by default. Deletes this wallet file and shared app data after the limit. Back up the seed first.';

  @override
  String get securitySettingsOff => 'Off';

  @override
  String get securitySettingsChange => 'Change';

  @override
  String get securitySettingsPasswordUnavailable =>
      'Password changes are not available yet.';

  @override
  String get securitySettingsBackup => 'Backup';

  @override
  String get securitySettingsSeedPhrase => 'Seed phrase';

  @override
  String get securitySettingsSeedPhraseHint => 'Shown on screen, in clear';

  @override
  String get securitySettingsSeedVault => 'Seed Vault';

  @override
  String get securitySettingsSeedVaultHint => 'An encrypted file of the seed';

  @override
  String get securitySettingsShow => 'Show';

  @override
  String get securitySettingsExport => 'Export';

  @override
  String get securitySettingsHardwareBackupHint => 'Not on a hardware wallet';

  @override
  String get securitySettingsSignMessage => 'Sign a message';

  @override
  String get securitySettingsVerifySignature => 'Verify a signature';

  @override
  String get securitySettingsRemoveWallet => 'Remove wallet';

  @override
  String get securitySettingsRemoveWalletHint =>
      'Needs the seed or a Seed Vault';

  @override
  String get securitySettingsMessage => 'Message';

  @override
  String get securitySettingsSignature => 'Signature';

  @override
  String get securitySettingsPublicKey => 'Public key';

  @override
  String get securitySettingsPaste => 'Paste';

  @override
  String get securitySettingsSign => 'Sign';

  @override
  String get securitySettingsVerify => 'Verify';

  @override
  String get securitySettingsFile => 'File';

  @override
  String get securitySettingsSignFile => 'Sign file';

  @override
  String get securitySettingsVerifyFile => 'Verify file';

  @override
  String get securitySettingsFileSignature => 'File signature';

  @override
  String get securitySettingsMessageVerified => 'Signature verified';

  @override
  String get securitySettingsInvalidMessageSignature =>
      'Message, signature or public key is invalid';

  @override
  String get securitySettingsFileVerified => 'File signature verified';

  @override
  String get securitySettingsInvalidFileSignature =>
      'File signature or public key is invalid';

  @override
  String get securitySettingsSignFailed => 'Could not sign. Try again.';

  @override
  String get securitySettingsVerifyFailed => 'Could not verify. Try again.';

  @override
  String get securitySettingsSaveFailed =>
      'Could not save this setting. Try again.';

  @override
  String get securitySettingsSessionChanged => 'Session changed. Try again.';

  @override
  String get securitySettingsLockChanged => 'Lock interval changed';

  @override
  String get securitySettingsLimitChanged => 'Wrong-password limit changed';

  @override
  String get securitySettingsChangePassword => 'Change password';

  @override
  String get securitySettingsPasswordRules =>
      'At least 8 characters, with upper and lower case letters, a number and a symbol.';

  @override
  String get securitySettingsCurrentPassword => 'Current password';

  @override
  String get securitySettingsNewPassword => 'New password';

  @override
  String get securitySettingsRepeatPassword => 'Repeat new password';

  @override
  String get securitySettingsPasswordChangeFailed =>
      'Password change did not complete.';

  @override
  String get securitySettingsSeedPrompt =>
      'Enter the wallet password to show it.';

  @override
  String get securitySettingsSeedWarning =>
      'Anyone with these words can spend from this wallet. Point at a word to read it, or press its number to keep it shown.';

  @override
  String get securitySettingsSeedFailed =>
      'Could not show the seed phrase. Try again.';

  @override
  String get securitySettingsVaultInfoTitle => 'Export Seed Vault';

  @override
  String get securitySettingsVaultInfo =>
      'A Seed Vault is a file of the seed, encrypted with a key you choose next. Keep the file and the key apart and offline. Lose either and the funds are lost.';

  @override
  String get securitySettingsVaultPromise =>
      'I will keep the Seed Vault and its key safe';

  @override
  String get securitySettingsVaultKey => 'Seed Vault key';

  @override
  String get securitySettingsVaultKeyRules =>
      'The key that opens the file. At least 8 characters, with upper and lower case letters, a number and a symbol.';

  @override
  String get securitySettingsRepeatVaultKey => 'Repeat key';

  @override
  String securitySettingsExportStep(int step) {
    return 'Step $step of 2';
  }

  @override
  String get securitySettingsVaultFileType => 'JSON file';

  @override
  String get securitySettingsVaultExported => 'Seed Vault exported';

  @override
  String get securitySettingsVaultExportFailed =>
      'Could not export the Seed Vault. Try again.';

  @override
  String get securitySettingsDone => 'Done';

  @override
  String get securitySettingsBack => 'Back';

  @override
  String get securitySettingsResetWallet => 'Reset wallet';

  @override
  String get securitySettingsResetWarning =>
      'Deletes this wallet file and shared app data from this computer. Keep the seed phrase, or a Seed Vault and its key, before continuing.';

  @override
  String get securitySettingsReset => 'Reset';

  @override
  String get walletSettingsAutoReceive => 'Auto-receive';

  @override
  String get walletSettingsAutoReceiveHint =>
      'Off: receive each transaction by hand';

  @override
  String get walletSettingsDesktopNotifications => 'Desktop notifications';

  @override
  String get walletSettingsLaunchAtStartup => 'Launch at startup';

  @override
  String get walletSettingsModes => 'Modes';

  @override
  String get walletSettingsModesHint =>
      'Auto: shown when the selected address owns one';

  @override
  String get walletSettingsAuto => 'Auto';

  @override
  String get walletSettingsOn => 'On';

  @override
  String get walletSettingsOff => 'Off';

  @override
  String get walletSettingsWallets => 'Wallets on this computer';

  @override
  String get walletSettingsWalletsHint => 'Rename, remove, add';

  @override
  String get walletSettingsMaintenance => 'Maintenance';

  @override
  String get walletSettingsClipboard => 'Clipboard watcher';

  @override
  String get walletSettingsClipboardHint =>
      'Offers to connect when a WalletConnect link is copied';

  @override
  String get walletSettingsSaveFailed => 'Could not save. Try again.';

  @override
  String get walletSettingsApplyFailed => 'Saved. Could not apply.';

  @override
  String get walletSettingsUnavailable => 'Unavailable';

  @override
  String get walletSettingsDelete => 'Delete';

  @override
  String get walletSettingsCacheHint =>
      'Clears network cache and closes the app';

  @override
  String get securitySettingsVaultExportUncertain =>
      'Export result unknown. Check the selected file.';

  @override
  String get securitySettingsPolicyUnavailable => 'Setting unavailable';

  @override
  String get appsSettingsWebApps => 'Web apps';

  @override
  String get appsSettingsWebAppsHint =>
      'Pages on this computer may ask to connect.';

  @override
  String get appsSettingsConnected => 'Connected';

  @override
  String get appsSettingsSite => 'Site';

  @override
  String get appsSettingsLastUsed => 'Last used';

  @override
  String get appsSettingsVia => 'Via';

  @override
  String get appsSettingsUnknown => 'Unknown';

  @override
  String get appsSettingsNone => 'None yet';

  @override
  String get appsSettingsWebApp => 'Web app';

  @override
  String get appsSettingsLink => 'Link';

  @override
  String get appsSettingsWalletConnect => 'WalletConnect';

  @override
  String get appsSettingsConnectByLink => 'Connect by link';

  @override
  String get appsSettingsWalletConnectLink => 'WalletConnect link';

  @override
  String get appsSettingsConnect => 'Connect';

  @override
  String get appsSettingsDisconnect => 'Disconnect';

  @override
  String get appsSettingsDisconnectPairing => 'Disconnect pairing';

  @override
  String get appsSettingsSessions => 'Sessions';

  @override
  String get appsSettingsPairings => 'Pairings';

  @override
  String get appsSettingsSession => 'Session';

  @override
  String get appsSettingsPairing => 'Pairing';

  @override
  String get appsSettingsTopic => 'Topic';

  @override
  String get appsSettingsUrl => 'URL';

  @override
  String get appsSettingsExpires => 'Expires';

  @override
  String get appsSettingsActive => 'Active';

  @override
  String get appsSettingsAcknowledged => 'Acknowledged';

  @override
  String appsSettingsSummary(int sessions, int pairings) {
    String _temp0 = intl.Intl.pluralLogic(
      sessions,
      locale: localeName,
      other: '$sessions sessions',
      one: '1 session',
    );
    String _temp1 = intl.Intl.pluralLogic(
      pairings,
      locale: localeName,
      other: '$pairings pairings',
      one: '1 pairing',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get appsSettingsOff => 'Off';

  @override
  String get appsSettingsStarting => 'Starting';

  @override
  String get appsSettingsNoFreePort => 'No free port';

  @override
  String get appsSettingsNotSaved => 'Not saved';

  @override
  String get appsSettingsUnavailable => 'Unavailable';

  @override
  String get appsSettingsFailed => 'Could not complete. Try again.';

  @override
  String get appsSettingsOutcomeUnknown => 'Outcome unknown. Check the list.';

  @override
  String get appsSettingsInvalidLink => 'Enter a WalletConnect link';

  @override
  String get appsSettingsScanScreen => 'Scan screen';

  @override
  String get appsSettingsCamera => 'Camera';

  @override
  String get appsSettingsInvalidQr => 'Invalid QR code';

  @override
  String get appsSettingsScreenPermission =>
      'Allow screen recording to scan a QR code.';

  @override
  String get addressesYourAddresses => 'Your addresses';

  @override
  String get addressesContacts => 'Contacts';

  @override
  String get addressesAddAddress => 'Add address';

  @override
  String get addressesAddContact => 'Add contact';

  @override
  String get addressesSelected => 'Selected';

  @override
  String get addressesContactName => 'Name';

  @override
  String get addressesContactAddress => 'Address';

  @override
  String get addressesEditContact => 'Edit contact';

  @override
  String addressesSent(String time) {
    return 'Sent $time';
  }

  @override
  String get addressesNoRecord => 'No record';

  @override
  String addressesAccountChain(String label) {
    return 'Account chain of $label';
  }

  @override
  String addressesBlockCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocks',
      one: '1 block',
    );
    return '$_temp0';
  }

  @override
  String get addressesBalancesUnavailable => 'Balances unavailable. Try again.';

  @override
  String get addressesAccountChainUnavailable =>
      'Account chain unavailable. Try again.';

  @override
  String get addressesSaveFailed => 'Changes were not saved. Try again.';

  @override
  String get addressesGenerationFailed => 'Address was not added. Try again.';

  @override
  String get addressesGenerationUncertain =>
      'Check Addresses before adding another.';

  @override
  String get addressesSavedReopen => 'Saved. Reopen Addresses.';

  @override
  String get addressesNameEmpty => 'Enter a name';

  @override
  String get addressesNameTooLong => 'Name is too long';

  @override
  String get addressesNameTaken => 'Name already exists';

  @override
  String get addressesAddressTaken => 'Address already exists';

  @override
  String get addressesInvalidAddress => 'Enter a valid address';

  @override
  String get addressesLabelTooLong => 'Label is too long';

  @override
  String get aboutSyrius => 'Syrius';

  @override
  String get aboutEmbeddedNode => 'Embedded node';

  @override
  String get aboutBuild => 'Build';

  @override
  String get aboutUnknown => 'Unknown';

  @override
  String get aboutBuildNumber => 'Build number';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutLinksHint => 'Docs, explorers, community';

  @override
  String get aboutComputer => 'This computer';

  @override
  String get aboutComputerHint => 'Paths, platform, wallet type';

  @override
  String get aboutLicences => 'Licences';

  @override
  String get aboutWhatChanged => 'What changed';

  @override
  String get aboutDownloadVerify => 'Download and verify';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutWalletType => 'Wallet type';

  @override
  String get aboutSdk => 'SDK';

  @override
  String get aboutBranch => 'Branch';

  @override
  String get aboutCommit => 'Commit';

  @override
  String get aboutCommitMessage => 'Commit message';

  @override
  String get aboutCommitDate => 'Commit date';

  @override
  String get aboutOrigin => 'Origin';

  @override
  String get aboutHostname => 'Hostname';

  @override
  String get aboutLocalIp => 'Local IP address';

  @override
  String get aboutOperatingSystem => 'Operating system';

  @override
  String get aboutProcessors => 'Processors';

  @override
  String get aboutPaths => 'Paths';

  @override
  String get aboutZenonData => 'Zenon data';

  @override
  String get aboutCache => 'Cache';

  @override
  String get aboutWallet => 'Wallet';

  @override
  String get aboutOpenLink => 'Open link';

  @override
  String get aboutOpenFolder => 'Open folder';

  @override
  String get aboutLicencesLoading => 'Loading';

  @override
  String get aboutLicencesFailed => 'Could not load licences. Try again.';

  @override
  String get aboutRetry => 'Retry';

  @override
  String get aboutWebsites => 'Websites';

  @override
  String get aboutExplorers => 'Explorers';

  @override
  String get aboutSocial => 'Social';

  @override
  String get aboutDocumentation => 'Documentation';

  @override
  String get aboutZenonNetwork => 'Zenon Network';

  @override
  String get aboutCommunityForum => 'Community forum';

  @override
  String get aboutZenonTools => 'Zenon Tools';

  @override
  String get aboutZenonOrg => 'Zenon ORG';

  @override
  String get aboutZenonHub => 'Zenon Hub';

  @override
  String get aboutExplorer => 'Explorer';

  @override
  String get aboutHubExplorer => 'Hub explorer';

  @override
  String get aboutTwitter => 'Twitter';

  @override
  String get aboutDiscord => 'Discord';

  @override
  String get aboutTelegram => 'Telegram';

  @override
  String get aboutMedium => 'Medium';

  @override
  String get aboutGithub => 'GitHub';

  @override
  String get aboutBitcoinTalk => 'Bitcoin Talk';

  @override
  String get aboutReddit => 'Reddit';

  @override
  String get aboutYoutube => 'YouTube';

  @override
  String get aboutWiki => 'Wiki';

  @override
  String get aboutCommunityWiki => 'Community wiki';

  @override
  String get aboutWhitepaper => 'Whitepaper';

  @override
  String get originalsTitle => 'Originals';

  @override
  String get originalsSince => 'Since Syrius 0.0.5, April 2022';

  @override
  String get originalsPlayLaunch => 'Play launch';

  @override
  String get originalsLaunch => 'Launch';

  @override
  String get originalsLaunchPlace => 'Every start, then the lock card';

  @override
  String get originalsGlobe => 'Globe';

  @override
  String get originalsGlobePlace => 'Welcome';

  @override
  String get originalsMap => 'Map';

  @override
  String get originalsMapPlace => 'Wallet ready';

  @override
  String get originalsPillar => 'Pillar';

  @override
  String get originalsPillarPlace => 'Your pillar, Spawn';

  @override
  String get originalsSentinel => 'Sentinel';

  @override
  String get originalsSentinelPlace => 'Your sentinel, Spawn';

  @override
  String get originalsZts => 'ZTS';

  @override
  String get originalsZtsPlace => 'Tokens, Create token';

  @override
  String get originalsPlasma => 'Generating plasma, in the strip';

  @override
  String get originalsHidden => 'Hidden balances';

  @override
  String get originalsEmpty => 'Empty lists';

  @override
  String get originalsHover => 'Hover to play';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get welcomeSubtitle => 'One wallet, every address you will need.';

  @override
  String get welcomeCreate => 'Create wallet';

  @override
  String get welcomeCreateHint => 'A new seed of 12 or 24 words';

  @override
  String get welcomeImport => 'Import wallet';

  @override
  String get welcomeImportHint => 'A seed, or a wallet file dropped here';

  @override
  String get welcomeHardware => 'Hardware wallet';

  @override
  String get welcomeHardwareHint => 'Ledger, with the Zenon app open';

  @override
  String get welcomeSettingsHint =>
      'Node and chain can be changed later in Settings.';

  @override
  String get swapListTitle => 'Swaps';

  @override
  String get swapListAll => 'All';

  @override
  String get swapListActive => 'Active';

  @override
  String get swapListCompleted => 'Completed';

  @override
  String get swapListReclaimable => 'Reclaimable';

  @override
  String get swapListToReclaim => 'To reclaim';

  @override
  String get swapListWaiting => 'Waiting';

  @override
  String get swapListStarting => 'Starting';

  @override
  String get swapListUnsuccessful => 'Unsuccessful';

  @override
  String get swapListYouSend => 'You send';

  @override
  String get swapListYouReceive => 'You receive';

  @override
  String get swapListCounterparty => 'Counterparty';

  @override
  String get swapListExpires => 'Expires';

  @override
  String get swapListStarted => 'Started';

  @override
  String get swapListYourDepositId => 'Your deposit ID';

  @override
  String get swapListCounterpartyDepositId => 'Counterparty deposit ID';

  @override
  String get swapListRate => 'Rate';

  @override
  String get swapListUnknown => 'Unknown';

  @override
  String get swapListWaitingNotice =>
      'Waiting for the counterparty. Keep Syrius open.';

  @override
  String get swapListExpiryNotice => 'Reclaim after the deposit expires.';

  @override
  String get swapListJoin => 'Join swap';

  @override
  String get swapListStart => 'Start swap';

  @override
  String get swapListOpen => 'Open swap';

  @override
  String get swapListReclaim => 'Reclaim';

  @override
  String get swapListRecover => 'Recover deposit';

  @override
  String get swapListTutorial => 'Swap tutorial';

  @override
  String get swapListClearHistory => 'Clear history';

  @override
  String get swapListDelete => 'Delete swap';

  @override
  String get swapListDeleteWarning => 'This cannot be undone.';

  @override
  String get swapListClearWarning =>
      'Active swaps are kept. This cannot be undone.';

  @override
  String get swapListUnavailable => 'Swaps unavailable. Try again.';

  @override
  String get swapListSourceChanged => 'Wallet or node changed. Refresh swaps.';

  @override
  String get swapListRefresh => 'Refresh';

  @override
  String get swapListMore => 'More';

  @override
  String get swapListHistoryFull => 'History full';

  @override
  String get swapListHistoryFullHint =>
      'Completed swaps may be removed when a new swap starts.';

  @override
  String get swapListCopyForThem => 'Copy for them';

  @override
  String get swapListDetails => 'Details';

  @override
  String get swapListSender => 'Sender';

  @override
  String get swapListRecipient => 'Recipient';

  @override
  String get swapListDepositId => 'Deposit ID';

  @override
  String get swapListInitialDepositId => 'Initial deposit ID';

  @override
  String get swapListHashlock => 'Hashlock';

  @override
  String get swapListYourAddress => 'Your address';

  @override
  String get swapListTokenStandard => 'Token standard';

  @override
  String get swapListExpired => 'Expired';

  @override
  String get swapListVerified => 'Verified';

  @override
  String get swapListFavorites => 'In your favorites';

  @override
  String get swapListUnverified => 'Not in your favorites';

  @override
  String get swapListPlasmaWait => 'Wait for plasma to generate.';

  @override
  String get acceleratorFund => 'Fund';

  @override
  String get acceleratorVoting => 'Voting';

  @override
  String get acceleratorNeedYourPillar => 'need your pillar';

  @override
  String get acceleratorDonate => 'Donate';

  @override
  String get acceleratorCreateProject => 'Create project';

  @override
  String get acceleratorActive => 'Active';

  @override
  String get acceleratorMine => 'Mine';

  @override
  String get acceleratorAll => 'All';

  @override
  String get acceleratorSearch => 'Search';

  @override
  String get acceleratorNewest => 'Newest';

  @override
  String get acceleratorOldest => 'Oldest';

  @override
  String get acceleratorProject => 'Project';

  @override
  String get acceleratorBudget => 'Budget';

  @override
  String get acceleratorVotes => 'Votes';

  @override
  String get acceleratorQuorum => 'Quorum';

  @override
  String get acceleratorStatus => 'Status';

  @override
  String get acceleratorYourVote => 'Your vote';

  @override
  String get acceleratorAccepted => 'Accepted';

  @override
  String get acceleratorPaid => 'Paid';

  @override
  String get acceleratorCompleted => 'Completed';

  @override
  String get acceleratorRejected => 'Rejected';

  @override
  String get acceleratorUnknown => 'Unknown';

  @override
  String get acceleratorReadFailed => 'Network error. Try again.';

  @override
  String acceleratorByOwner(String owner, String age) {
    return 'by $owner · $age';
  }

  @override
  String acceleratorVoteTally(int yes, int no, int abstain) {
    return '$yes · $no · $abstain';
  }

  @override
  String get acceleratorNoneYet => 'None yet';

  @override
  String get acceleratorRefresh => 'Refresh';

  @override
  String get swapListStatus => 'Status';

  @override
  String get walletReadyTitle => 'Your wallet is ready';

  @override
  String get walletReadyFirstAddress => 'Address 1';

  @override
  String get walletReadyOpen => 'Open wallet';

  @override
  String get walletReadyCopy => 'Copy address';

  @override
  String get walletReadyUnknown => 'Unknown';

  @override
  String get walletReadySeed => 'Seed';

  @override
  String get walletReadyConfirm => 'Confirm';

  @override
  String get walletReadyPassword => 'Password';

  @override
  String get walletReadyReady => 'Ready';

  @override
  String get walletReadyDevice => 'Device';

  @override
  String get entryBack => 'Back';

  @override
  String get entryReady => 'Ready';

  @override
  String get importWalletTitle => 'Import your wallet';

  @override
  String get importSeedOrFile => 'Seed or file';

  @override
  String get importSeedHint => 'Type your seed, or drop a wallet file';

  @override
  String get importFileHint =>
      'Any file name. It is accepted if it decrypts as a Syrius keyfile.';

  @override
  String get importFileSelected => 'Wallet file selected';

  @override
  String get importFileInvalid => 'Not a Syrius wallet file';

  @override
  String get importSeedInvalid => 'Check the seed words and their order.';

  @override
  String importWordCount(int count, int total) {
    return '$count of $total';
  }

  @override
  String get importUnlockTitle => 'Unlock the wallet file';

  @override
  String get importUnlockHint => 'Enter the password it was saved with';

  @override
  String get importPasswordIncorrect => 'Incorrect password';

  @override
  String get importDecryptFailed => 'Could not unlock this file. Try again.';

  @override
  String get importPasswordTitle => 'Create a wallet password';

  @override
  String get importPasswordHint => 'You will need it to unlock the wallet';

  @override
  String get importConfirmPassword => 'Confirm password';

  @override
  String get seedQuizTitle => 'Confirm your seed';

  @override
  String get seedQuizSeed => 'Seed';

  @override
  String get seedQuizConfirm => 'Confirm';

  @override
  String seedQuizWord(int position) {
    return 'Word $position';
  }

  @override
  String seedQuizProgress(int count) {
    return '$count of 3 done.';
  }

  @override
  String get seedQuizInvalid => 'Check your seed before continuing.';

  @override
  String get entryPasswordRule =>
      'At least 8 characters, with an upper and a lower case letter, a number and a symbol';

  @override
  String get acceleratorProjects => 'Projects';

  @override
  String get acceleratorArticle => 'Article';

  @override
  String get acceleratorExplorer => 'Explorer';

  @override
  String get acceleratorOwner => 'Owner';

  @override
  String get acceleratorCreated => 'Created';

  @override
  String get acceleratorPhases => 'Phases';

  @override
  String get acceleratorCreatePhase => 'Create phase';

  @override
  String get acceleratorUpdatePhase => 'Update phase';

  @override
  String acceleratorVoteAs(String name, String target) {
    return 'Vote as $name, $target';
  }

  @override
  String acceleratorPhaseNumber(int number) {
    return 'Phase $number';
  }

  @override
  String get acceleratorYes => 'Yes';

  @override
  String get acceleratorNo => 'No';

  @override
  String get acceleratorAbstain => 'Abstain';

  @override
  String get acceleratorProof => 'Proof';

  @override
  String get acceleratorVotingClosed => 'Voting closed';

  @override
  String get acceleratorVoteUnavailable => 'Voting unavailable';

  @override
  String get acceleratorSessionChanged => 'Wallet changed. Reopen this view.';

  @override
  String get acceleratorActionUnknown => 'Outcome unknown. Check activity.';

  @override
  String get acceleratorActionSubmitted => 'Submitted';

  @override
  String get acceleratorActionRefused =>
      'Action refused. Refresh and try again.';

  @override
  String get acceleratorActionHeld => 'Original action pending';

  @override
  String get acceleratorNewAction => 'New action';

  @override
  String get acceleratorDetails => 'Details';

  @override
  String get acceleratorSubmit => 'Submit';

  @override
  String get acceleratorName => 'Name';

  @override
  String get acceleratorDescription => 'Description';

  @override
  String get acceleratorUrl => 'URL';

  @override
  String get acceleratorZnnBudget => 'ZNN budget';

  @override
  String get acceleratorQsrBudget => 'QSR budget';

  @override
  String get acceleratorDonationZnn => 'ZNN donation';

  @override
  String get acceleratorDonationQsr => 'QSR donation';

  @override
  String get acceleratorContinue => 'Continue';

  @override
  String get acceleratorCancel => 'Cancel';

  @override
  String get acceleratorBack => 'Back';

  @override
  String acceleratorCreateFee(String amount) {
    return 'Fee: $amount';
  }

  @override
  String get acceleratorChangeVote => 'Your vote can be changed.';

  @override
  String get importFileOpenFailed =>
      'Could not open the file picker. Try again.';

  @override
  String get swapActionCreateDeposit => 'Create deposit';

  @override
  String get swapActionNewDeposit => 'New deposit';

  @override
  String get swapActionFindDeposit => 'Find deposit';

  @override
  String get swapActionEnterDepositId => 'Enter the deposit ID';

  @override
  String get swapActionEnterAddress => 'Enter a counterparty';

  @override
  String get swapActionEnterAmount => 'Enter an amount';

  @override
  String get swapActionNotEnough => 'Not enough balance';

  @override
  String get swapActionSending => 'Sending';

  @override
  String get swapActionSearching => 'Searching';

  @override
  String get swapActionSubmitted => 'Submitted';

  @override
  String get swapActionUnlock => 'Unlock';

  @override
  String get swapActionUnlockSubmitted => 'Unlock submitted';

  @override
  String get swapActionReclaimSubmitted => 'Reclaim submitted';

  @override
  String get swapActionUnknown =>
      'Result unknown. Check this deposit before another action.';

  @override
  String get swapActionRefused => 'Action refused. Refresh swaps.';

  @override
  String get swapActionReadFailed => 'Deposit unavailable. Refresh swaps.';

  @override
  String get swapActionDepositOnly =>
      'Only your deposit is created. Agree the other side separately.';

  @override
  String swapActionTiming(int initialHours, int counterHours) {
    return '$initialHours h initial · $counterHours h counter';
  }

  @override
  String swapActionDiscovery(int hours, int minutes) {
    return '$hours h discovery · $minutes min completion margin';
  }

  @override
  String get swapActionExperimental =>
      'Experimental. Check both tokens and amounts before unlocking.';

  @override
  String get swapActionNoRequestedTerms => 'No requested amount is recorded.';

  @override
  String get swapActionRecorded => 'Recorded';

  @override
  String get swapActionChainPending => 'Chain status unknown';

  @override
  String get swapActionDepositVerified => 'Deposit verified';

  @override
  String get swapActionCanReclaim => 'Deposit expired. Reclaim it explicitly.';

  @override
  String get swapActionDepositLive => 'Deposit is live';

  @override
  String get swapActionConfirmAmount =>
      'Check the counterparty token and amount before unlocking.';

  @override
  String get swapActionFreshDetails => 'Refresh deposit';

  @override
  String get swapActionPaste => 'Paste';

  @override
  String get swapActionTitle => 'Swap';

  @override
  String get receiveOperationFailed => 'Could not receive. Refresh activity.';

  @override
  String get walletCreationUnavailable =>
      'Wallet setup is unavailable. Your original attempt has been kept.';
}
