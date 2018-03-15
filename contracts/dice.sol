pragma solidity ^0.4.19;

/// @title a dice game
/// @author peara
contract Dice
{
  enum State
  {
    WaitingForPlayers,
    WaitingForDice1,
    WaitingForDice2,
    Complete
  }

  enum Event
  {
    Join,
    WaitingForDice,
    Roll,
    Expire,
    Complete,
    Withdraw
  }

  address public player1;
  address public player2;
  uint public betAmount;
  mapping(address => uint) public dices;
  mapping(address => uint) public earning;
  uint256 public maxRevealSeconds = 60 * 5;
  address public owner;
  State public state;
  uint256 public expiredAt;

  event GameEvent(address indexed gameAddress, address indexed player, Event indexed eventType);

  uint public constant DICE_SIZE = 100;
  uint public constant MIN_BET = 0.001 ether;
  uint public constant MAX_BET = 1000 ether;

  function Dice() public payable
  {
    player1 = msg.sender;
    owner = msg.sender;
    require (msg.value >= MIN_BET && msg.value <= MAX_BET);
    betAmount = msg.value;
    state = State.WaitingForPlayers;
  }

  /// @notice Join let an external owned address joins the game
  function join() public payable
  {
    require (state == State.WaitingForPlayers);
    require (player1 != msg.sender);
    require (player2 == 0);
    require (msg.value == betAmount);

    state = State.WaitingForDice1;
    expiredAt = now + maxRevealSeconds;

    GameEvent(address(this), msg.sender, Event.Join);
    GameEvent(address(this), player1, Event.WaitingForDice);
    GameEvent(address(this), player2, Event.WaitingForDice);
  }

  /// @notice Roll let players roll a dice
  function roll() public
  {
    // must not completed or still waiting for player
    require (state == State.WaitingForDice1 || state == State.WaitingForDice2);
    // sender must be a player
    require (msg.sender == player1 || msg.sender == player2);
    // sender must not already roll
    require (dices[msg.sender] == 0);

    // Roll a dice
    // NOTE: this can be exploit by players by choosing block time
    uint256 hashResult = uint256(keccak256(address(this), now, msg.sender));
    uint32 randomSeed = uint32(hashResult >> 0)
                      ^ uint32(hashResult >> 32)
                      ^ uint32(hashResult >> 64)
                      ^ uint32(hashResult >> 96)
                      ^ uint32(hashResult >> 128)
                      ^ uint32(hashResult >> 160)
                      ^ uint32(hashResult >> 192)
                      ^ uint32(hashResult >> 224);

    uint32 randomNumber = randomSeed;
    uint32 randMax = 0xFFFFFFFF; // We use the whole 32 bit range

    // Generate random numbers until we get a value in the unbiased range (see below)
    do
    {
        randomNumber ^= (randomNumber >> 11);
        randomNumber ^= (randomNumber << 7) & 0x9D2C5680;
        randomNumber ^= (randomNumber << 15) & 0xEFC60000;
        randomNumber ^= (randomNumber >> 18);
    }
    // Since DICE_SIZE is not divisible by randMax, using modulo below will introduce bias for
    // numbers at the end of the randMax range. To remedy this, we discard these out of range numbers
    // and generate additional numbers until we are in the largest range divisble by DICE_SIZE.
    // This range will ensure we do not introduce any modulo bias
    while(randomNumber >= (randMax - (randMax % DICE_SIZE)));

    dices[msg.sender] = randomNumber % DICE_SIZE;
    if (state == State.WaitingForDice1) {
      state = State.WaitingForDice2;
    } else if (state == State.WaitingForDice2) {
      state = State.Complete;
    }
    GameEvent(address(this), msg.sender, Event.Roll);
    if (state == State.Complete) _completeGame();
  }

  /// @notice Expire will expire the game
  ///    if only one player roll the dice before expiredAt
  ///    After that, that player can withdraw all ether
  function expire() public
  {
    require (state == State.WaitingForDice2);
    require (dices[msg.sender] > 0);
    require (now < expiredAt);

    GameEvent(address(this), player1, Event.Expire);
    GameEvent(address(this), player2, Event.Expire);

    earning[msg.sender] = this.balance;
    GameEvent(address(this), msg.sender, Event.Withdraw);
  }

  function _completeGame() private
  {
    require (dices[player1] > 0 && dices[player2] > 0);

    // notify both players that the game is finished
    GameEvent(address(this), player1, Event.Complete);
    GameEvent(address(this), player2, Event.Complete);

    if (dices[player1] > dices[player2]) {
      earning[player1] = this.balance;
      GameEvent(address(this), player1, Event.Withdraw);
    } else if (dices[player2] > dices[player1]) {
      earning[player2] = this.balance;
      GameEvent(address(this), player2, Event.Withdraw);
    } else {
      // player1 may gain 1 more wei
      earning[player2] = this.balance / 2;
      earning[player1] = this.balance - earning[player2];
      GameEvent(address(this), player1, Event.Withdraw);
      GameEvent(address(this), player2, Event.Withdraw);
    }
  }

  function withdraw() public
  {
    require (earning[msg.sender] > 0);
    require (this.balance >= earning[msg.sender]);

    earning[msg.sender] = 0;
    assert(msg.sender.send(earning[msg.sender]));
  }
}
