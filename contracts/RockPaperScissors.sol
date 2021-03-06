pragma solidity ^0.5.0;

import {SafeMath} from "./SafeMath.sol";

contract RockPaperScissors {

    using SafeMath for uint256;

    /*
     * State Variables
     */

    enum Stages {lobby, active, revealing, finals}

    struct Game {
        address _player1;
        address _player2;
        uint256 _deadline;
        uint256 _wager;
        Stages _stage;
        bytes32 _actionHashP1;
        bytes32 _actionHashP2;
        uint8 _actionP1;
        uint8 _actionP2;
    }
    // _actionPX: rock = 1, paper = 2, scissors = 3
    // _actionHash = hash(x, salt)

    mapping(address => uint256) public balances;
    mapping(uint256 => Game) public activeGames;

    uint256 private gameCounter = 0;


    /*
     * Events
     */

    event LogDeposit(address indexed user, uint256 amount);
    event LogWithdrawal(address indexed user, uint256 amount);
    event LogNewGame(uint256 indexed gameId, address indexed player1, address indexed player2, uint256 wager);
    event LogPlayer2Joined(uint256 indexed gameId, address indexed player2);
    event LogActionSubmitted(uint256 indexed gameId, address player);
    event LogActionRevealed(uint256 indexed gameId, address player, uint8 action);
    event LogGameFinished(uint256 indexed gameId, address indexed winner);


    /*
     * General Functions
     */

    function() external {
        revert("Call specific function");
    }

    function deposit() public payable {
        balances[msg.sender] = balances[msg.sender].add(msg.value);
        emit LogDeposit(msg.sender, msg.value);
    }

    function withdraw() public {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance available");
        balances[msg.sender] = 0;
        msg.sender.transfer(amount);
        emit LogWithdrawal(msg.sender, amount);
    }


    /*
     * Game Logic Functions
     */

    function newGame(address player2, uint256 wager) public returns (uint256) {
        require(balances[msg.sender] >= wager, "Balance to low, please deposit funds");
        balances[msg.sender] -= wager;

        Game memory gameObj;
        gameObj._player1 = msg.sender;
        gameObj._player2 = player2;
        gameObj._wager = wager;
        gameObj._deadline = block.timestamp + 5 minutes;
        gameObj._stage = Stages.lobby;

        gameCounter++;
        activeGames[gameCounter] = gameObj;
        emit LogNewGame(gameCounter, msg.sender, player2, wager);
    }

    function joinGame(uint256 gameId) public payable {
        Game storage gameObj = activeGames[gameId];
        require(gameObj._stage == Stages.lobby, "Player 2 already joined");
        require(balances[msg.sender] >= gameObj._wager, "Balance to low, please deposit funds");
        balances[msg.sender] -= gameObj._wager;

        if (gameObj._player2 == address(0)) {
            gameObj._player2 == msg.sender;
            /// @notice: p1 can submit address(0) during newGame() to make the game public
        } else {
            require(msg.sender == gameObj._player2, "Wrong player 2, lobby is private");
        }

        gameObj._stage = Stages.active;
        gameObj._deadline = block.timestamp + 5 minutes;
        emit LogPlayer2Joined(gameId, msg.sender);
    }

    function submitAction(uint256 gameId, bytes32 actionHash) public {
        Game storage gameObj = activeGames[gameId];
        require(gameObj._stage == Stages.active, "Game is not in submitting stage");

        if (msg.sender == gameObj._player1) {
            require(gameObj._actionHashP1.length == 0, "P1 action has already been submitted");
            gameObj._actionHashP1 = actionHash;

        } else if(msg.sender == gameObj._player2) {
            require(gameObj._actionHashP2.length == 0, "P2 action has already been submitted");
            gameObj._actionHashP2 = actionHash;

        } else {
            revert("Must be player1 or player2");
        }

        emit LogActionSubmitted(gameId, msg.sender);
        if (gameObj._actionHashP1.length != 0 && gameObj._actionHashP2.length != 0) {
            gameObj._stage = Stages.revealing;
            gameObj._deadline = block.timestamp + 5 minutes;
        }
    }

    function revealAction(uint256 gameId, uint8 action, string memory salt) public {
        Game storage gameObj = activeGames[gameId];
        require(gameObj._stage == Stages.revealing, "Game is not in reveal stage");

        bytes32 hashValue = keccak256(abi.encodePacked(action, salt));

        if (msg.sender == gameObj._player1) {
            require(hashValue == gameObj._actionHashP1, "Revealed action does not match hashed action");
            require(action == 1 || action == 2 || action == 3, "Revealed action violates game rules");
            // if P1 violates rules -> P2 can wait for deadline to pass and resolve game in his favour
            gameObj._actionP1 = action;
            delete gameObj._actionHashP1;

        } else if (msg.sender == gameObj._player2) {
            require(hashValue == gameObj._actionHashP2, "Revealed action does not match hashed action");
            require(action == 1 || action == 2 || action == 3, "Revealed action violates game rules");
            gameObj._actionP2 = action;
            delete gameObj._actionHashP2;

        } else {
            revert("Must be player1 or player2");
        }

        emit LogActionRevealed(gameId, msg.sender, action);
        if (gameObj._actionP1 != 0 && gameObj._actionP2 != 0) {
            gameObj._stage = Stages.finals;
        }
    }

    function finishGame(uint256 gameId) public returns (uint8) {
        Game storage gameObj = activeGames[gameId];
        require(gameObj._stage == Stages.finals, "Game is not in finals stage");

        if (gameObj._actionP1 == gameObj._actionP2) {
            _draw(gameId);

        } else if (gameObj._actionP1 == 1) {
            if (gameObj._actionP2 == 2) {
                // P1 rock & P2 paper -> P2 wins
                _p2Wins(gameId);
            } else {
                // P1 rock & P2 scissors -> P1 wins
                _p1Wins(gameId);
            }

        } else if (gameObj._actionP1 == 2) {
            if (gameObj._actionP2 == 1) {
                // P1 paper & P2 rock -> P1 wins
                _p1Wins(gameId);
            } else {
                // P1 paper & P2 scissors -> P2 wins
                _p2Wins(gameId);
            }

        } else {
            if (gameObj._actionP2 == 1) {
                // P1 scissors & P2 rock -> P2 wins
                _p2Wins(gameId);
            } else {
                // P1 scissors & P2 paper -> P1 wins
                _p1Wins(gameId);
            }
        }
    }

    function resolveGame(uint256 gameId) public {
        Game storage gameObj = activeGames[gameId];

        if (gameObj._stage == Stages.lobby) {
            require(block.timestamp > gameObj._deadline, "Player 2 still has time to join the game");
            _draw(gameId);

        } else if (gameObj._stage == Stages.active) {
            require(block.timestamp > gameObj._deadline, "Players still have time to submit their actions");
            if (gameObj._actionHashP1.length == 0 && gameObj._actionHashP2.length == 0) {
                // both players did not submit their action -> draw
                _draw(gameId);
            } else if (gameObj._actionHashP1.length == 0) {
                // P1 did not submit action -> P2 wins
                _p2Wins(gameId);
            } else {
                // P2 did not submit action -> P1 wins
                _p1Wins(gameId);
            }

        } else if (gameObj._stage == Stages.revealing) {
            require(block.timestamp > gameObj._deadline, "Players still have time to reveal their actions");
            if (gameObj._actionP1 == 0 && gameObj._actionP2 == 0) {
                // both players did not reveal their action -> draw
                _draw(gameId);
            } else if (gameObj._actionP1 == 0) {
                // P1 did not reveal action -> P2 wins
                _p2Wins(gameId);
            } else {
                // P2 did not reveal action -> P1 wins
                _p1Wins(gameId);
            }

        } else {
            // gameObj._stage is finals -> game must be finished via finishGame()
            revert("game should be finished via appropriate function");
        }
    }


    /*
     * Internal Functions
     */

    function _p1Wins(uint256 gameId) internal {
        Game storage gameObj = activeGames[gameId];
        balances[gameObj._player1] = balances[gameObj._player1].add(gameObj._wager * 2);
        emit LogGameFinished(gameId, gameObj._player1);
        delete activeGames[gameId];
    }

    function _p2Wins(uint256 gameId) internal {
        Game storage gameObj = activeGames[gameId];
        balances[gameObj._player2] = balances[gameObj._player2].add(gameObj._wager * 2);
        emit LogGameFinished(gameId, gameObj._player2);
        delete activeGames[gameId];
    }

    function _draw(uint256 gameId) internal {
        Game storage gameObj = activeGames[gameId];
        balances[gameObj._player1] = balances[gameObj._player1].add(gameObj._wager);
        balances[gameObj._player2] = balances[gameObj._player1].add(gameObj._wager);
        emit LogGameFinished(gameId, address(0));
        delete activeGames[gameId];
    }
}