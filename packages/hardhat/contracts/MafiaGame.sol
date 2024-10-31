// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Treasury.sol";

contract MafiaGame {
	enum Role {
		Assassin,
		Police,
		Citizen
	}
	enum GameState {
		Waiting,
		AssigningRoles,
		Night,
		Day,
		Finalizing,
		Finished
	}

	struct Player {
		address playerAddress;
		Role role;
		bool isAlive;
		bool hasVoted;
	}

	Treasury public treasury;
	GameState public currentState;
	address public activePlayer;
	address[] public playerAddresses;
	address[] public winners;
	mapping(address => Player) public players;
	mapping(address => uint) public votes;

	uint public totalVotes;
	uint public startTime;
	address public lastKilled;

	event GameStarted();
	event RoleAssigned(address indexed player, Role role);
	event NightNarration(address indexed killer, address indexed victim);
	event PlayerVoted(address indexed voter, address indexed target);
	event VotingRestarted();
	event DayNarration(address indexed victim);
	event VotingResult(
		address indexed mostVoted,
		uint highestVotes,
		bool isTie
	);
	event PrizeClaimed(address indexed winner, uint amount);
	event GameEnded(address[] winners);
	event GameReset();

	modifier onlyActivePlayer() {
		require(msg.sender == activePlayer, "Only active player allowed");
		_;
	}

	modifier onlyInState(GameState state) {
		require(currentState == state, "Invalid game state!");
		_;
	}

	modifier onlyWinner() {
		require(
			winners.length > 0 && winners[0] == activePlayer,
			"Caller is not the winner!"
		);
		_;
	}

	constructor(address _treasuryAddress) {
		treasury = Treasury(_treasuryAddress);
		currentState = GameState.Waiting;
	}

	function joinGame() external payable onlyInState(GameState.Waiting) {
		require(msg.value == 0.1 ether, "Must pay 0.1 ETH to join");
		require(playerAddresses.length == 0, "Game already has active player");

		activePlayer = msg.sender;
		playerAddresses.push(msg.sender);
		players[msg.sender] = Player(msg.sender, Role.Assassin, true, false);
		treasury.deposit{ value: msg.value }(msg.sender);

		addVirtualPlayers();
		startGame();
	}

	function addVirtualPlayers() private {
		require(
			address(this).balance >= 0.3 ether,
			"Insufficient balance for virtual players"
		);

		for (uint i = 1; i <= 3; i++) {
			address virtualPlayer = address(uint160(i));
			playerAddresses.push(virtualPlayer);
			treasury.deposit{ value: 0.1 ether }(virtualPlayer);
			players[virtualPlayer] = Player(
				virtualPlayer,
				Role(
					i == 1
						? Role.Assassin
						: i == 2
							? Role.Police
							: Role.Citizen
				),
				true,
				false
			);
		}
	}

	function startGame() private {
		currentState = GameState.AssigningRoles;
		startTime = block.timestamp;
		emit GameStarted();

		for (uint i = 0; i < playerAddresses.length; i++) {
			emit RoleAssigned(
				playerAddresses[i],
				players[playerAddresses[i]].role
			);
		}

		currentState = GameState.Night;
	}

	function assassinKill(
		address target
	) external onlyActivePlayer onlyInState(GameState.Night) {
		require(players[target].isAlive, "Target is already dead!");

		players[target].isAlive = false;
		lastKilled = target;
		startTime = block.timestamp;
		currentState = GameState.Day;
		emit NightNarration(msg.sender, target);
	}

	function voteToKill(
		address target
	) external onlyActivePlayer onlyInState(GameState.Day) {
		require(players[target].isAlive, "Target is already dead!");
		players[activePlayer].hasVoted = true;
		votes[target]++;
		totalVotes = 3;

		players[target].isAlive = false;
		lastKilled = target;
		currentState = GameState.Finalizing;
		winners.push(activePlayer);

		emit PlayerVoted(activePlayer, target);
		emit DayNarration(target);
		emit VotingResult(target, votes[target], false);
	}

	function resetVoting() private {
		for (uint i = 0; i < playerAddresses.length; i++) {
			players[playerAddresses[i]].hasVoted = false;
			votes[playerAddresses[i]] = 0;
		}
		totalVotes = 0;
		startTime = block.timestamp;
	}

	function claimPrize()
		external
		onlyActivePlayer
		onlyWinner
		onlyInState(GameState.Finalizing)
	{
		uint totalPrize = treasury.getBalance();
		treasury.distributePrize(payable(activePlayer), totalPrize);

		currentState = GameState.Finished;
		resetGame();
		emit GameEnded(winners);
	}

	function resetGame() private {
		for (uint i = 0; i < playerAddresses.length; i++) {
			delete players[playerAddresses[i]];
			delete votes[playerAddresses[i]];
		}

		treasury.resetBalances(playerAddresses);
		delete playerAddresses;
		delete winners;
		delete lastKilled;
		delete activePlayer;
		totalVotes = 0;
		startTime = 0;
		currentState = GameState.Waiting;
		emit GameReset();
	}

	function getAllPlayers() public view returns (Player[] memory) {
		Player[] memory allPlayers = new Player[](playerAddresses.length);
		for (uint256 i = 0; i < playerAddresses.length; i++) {
			allPlayers[i] = players[playerAddresses[i]];
		}
		return allPlayers;
	}

	function getAllWinners() public view returns (address[] memory) {
		address[] memory allWinners = new address[](1);
		allWinners[0] = activePlayer;

		return allWinners;
	}

	receive() external payable {}
}
