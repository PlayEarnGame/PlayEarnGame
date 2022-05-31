// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PEGv3 is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    //constructor() initializer {}

    address private taxWallet;

    bool public pollRunning;
    uint public currentVote;
    mapping(uint256 => mapping(address => bool)) public alreadyVoted;
    mapping(uint256 => uint256[]) public votes;

    event PollResults(uint256 totalVotes, uint256 votesForArgA, uint256 votesForArgB);

    mapping(address => uint256) private _staked_peg;
    mapping(address => uint256) private _stake_time;

    mapping(address => bool) public alreadySwapped;

    event Stake(uint256 amount,uint time);
    event Claim(uint256 amount,uint time);

    function initialize() initializer public {
        __ERC20_init("PlayEarnGame.com", "$PEG");
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
	    __PEG_init();

        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function transfer(address to, uint256 amount) public virtual whenNotPaused override returns(bool){
        uint256 toBurn = amount / 100;
        uint256 toTax = amount / 50;
        uint256 toTransfer = amount - (toBurn + toTax);
        uint256 staked = _staked_peg[msg.sender] * 10 ** decimals();
        require(balanceOf(msg.sender) - staked >= amount, 'ERC20: transfer amount exceeds balance');
        super.transfer(taxWallet,toTax);
        super.burn(toBurn);
        super.transfer(to,toTransfer);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual whenNotPaused override returns(bool){
        uint256 toBurn = amount / 100;
        uint256 toTax = amount / 50;
        uint256 toTransfer = amount - (toBurn + toTax);
        uint256 staked = _staked_peg[from] * 10 ** decimals();
        require(balanceOf(from) - staked >= amount, 'ERC20: transfer amount exceeds balance');
        super.transferFrom(from,taxWallet,toTax);
        super.burnFrom(from,toBurn);
        super.transferFrom(from,to,toTransfer);
        return true;
    }

    function newPoll() public whenNotPaused onlyOwner{
        pollRunning = true;
        currentVote++;
    }
    
    function endPoll() public whenNotPaused onlyOwner{
        pollRunning = false;
        uint256 k = 0;
        for( uint i = 0; i < votes[currentVote].length; i++){
            if( votes[currentVote][i] == 1)
                k++;
        }
        emit PollResults(votes[currentVote].length, k, (votes[currentVote].length-k));
    }
    
    function vote(uint256 arg) whenNotPaused external{
        require(pollRunning == true, 'ERC20: nothing to vote about');
        require( _staked_peg[msg.sender] > 0, 'ERC20: not allowed to vote');
        require(!alreadyVoted[currentVote][msg.sender], 'ERC20: already voted');
        require(arg == 0 || arg == 1, 'ERC20: this is not an argument of this vote');
        votes[currentVote].push(arg);
        alreadyVoted[currentVote][msg.sender] = true;
    }

    function __PEG_init() initializer internal{
        pollRunning = false;
	    currentVote = 0;
	    taxWallet = 0x9a78f38fd8613fc5DECadD4A148e08a59AFEF4A0;
    }

    function approve(address spender, uint256 amount) whenNotPaused public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function stake(uint256 amount) whenNotPaused public returns (bool) {
        require(_staked_peg[msg.sender]==0,'ERC20: already staking');
        require(amount >= 5000,'ERC20: stake amount to low');
        uint256 balance = balanceOf(msg.sender)/10 ** decimals();
        require(balance >= amount,'ERC20: stake amount exceeds balance');
        _staked_peg[msg.sender] = amount;
        _stake_time[msg.sender] = block.timestamp;
        emit Stake(balance,block.timestamp);
        return true;
    }
    
    function unstake() whenNotPaused public returns (bool) {
        claim();
        _staked_peg[msg.sender] = 0;
        _stake_time[msg.sender] = 0;
        return true;
    }

    function claim() whenNotPaused public returns (bool) {
        uint256 apr_rate;
        require(_staked_peg[msg.sender] >= 5000,'ERC20: stake amount not exists');
        require((block.timestamp - _stake_time[msg.sender]) >= 86400,'ERC20: you have been earning for less than 24h');
        if(_staked_peg[msg.sender]<10000)
           apr_rate = 137;
        else if(_staked_peg[msg.sender]<30000)
            apr_rate = 219;
        else if(_staked_peg[msg.sender]<50000)
            apr_rate = 411;
        else
            apr_rate = 548;
        uint256 amount = ((block.timestamp - _stake_time[msg.sender])/864) * apr_rate * _staked_peg[msg.sender] * 10 ** 10;
        _mint(msg.sender, amount);
        emit Claim(amount,block.timestamp);
        _stake_time[msg.sender] = block.timestamp;
        return true;
    }

    function swap() whenNotPaused public returns (bool) {
        require(alreadySwapped[msg.sender]==false,'ERC20: already swapped');
        address owner = 0xb776D054824Dc9CAdF8f92cf444616467EbF7bAC;
        IERC20 _delegate = IERC20(0xf4a005217FDA6c1AF02114D1b0Aa08b6d86aa387);
        uint result = _delegate.balanceOf(msg.sender);
        _approve(owner, msg.sender, result);
        transferFrom(owner, msg.sender, result);
        alreadySwapped[msg.sender] = true;
        return true;
    }
}