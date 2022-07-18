// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./interfaces/ITicketBooth.sol";
import "./abstract/Operatable.sol";
import "./abstract/TerminalUtility.sol";

import "./libraries/Operations.sol";

import "./Tickets.sol";


contract TicketBooth is TerminalUtility, Operatable, ITicketBooth {
    // --- public immutable stored properties --- //

    /// @notice The Projects contract which mints ERC-721's that represent project ownership and transfers.
    IProjects public immutable override projects;

    // --- public stored properties --- //

    // Each project's ERC20 Ticket tokens.
    mapping(uint256 => ITickets) public override ticketsOf;

    // Each holder's balance of staked Tickets for each project.
    mapping(address => mapping(uint256 => uint256))
        public
        override stakedBalanceOf;

    // The total supply of 1155 tickets for each project.
    mapping(uint256 => uint256) public override stakedTotalSupplyOf;

    // The amount of each holders tickets that are locked.
    mapping(address => mapping(uint256 => uint256))
        public
        override lockedBalanceOf;

    // The amount of each holders tickets that are locked by each address.
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public
        override lockedBalanceBy;

    // --- external views --- //

    
    function totalSupplyOf(uint256 _projectId)
        external
        view
        override
        returns (uint256 supply)
    {
        supply = stakedTotalSupplyOf[_projectId];
        ITickets _tickets = ticketsOf[_projectId];
        if (_tickets != ITickets(address(0)))
            supply = supply + _tickets.totalSupply();
    }

    function balanceOf(address _holder, uint256 _projectId)
        external
        view
        override
        returns (uint256 balance)
    {
        balance = stakedBalanceOf[_holder][_projectId];
        ITickets _ticket = ticketsOf[_projectId];
        if (_ticket != ITickets(address(0)))
            balance = balance + _ticket.balanceOf(_holder);
    }

    // --- external transactions --- //

    
    constructor(
        IProjects _projects,
        IOperatorStore _operatorStore,
        ITerminalDirectory _terminalDirectory
    ) Operatable(_operatorStore) TerminalUtility(_terminalDirectory) {
        projects = _projects;
    }

    
    function issue(
        uint256 _projectId,
        string calldata _name,
        string calldata _symbol
    )
        external
        override
        requirePermission(
            projects.ownerOf(_projectId),
            _projectId,
            Operations.Issue
        )
    {
        // There must be a name.
        require((bytes(_name).length > 0), "TicketBooth::issue: EMPTY_NAME");

        // There must be a symbol.
        require(
            (bytes(_symbol).length > 0),
            "TicketBooth::issue: EMPTY_SYMBOL"
        );

        // Only one ERC20 ticket can be issued.
        require(
            ticketsOf[_projectId] == ITickets(address(0)),
            "TicketBooth::issue: ALREADY_ISSUED"
        );

        // Create the contract in this TerminalV1 contract in order to have mint and burn privileges.
        // Prepend the strings with standards.
        ticketsOf[_projectId] = new Tickets(_name, _symbol);

        emit Issue(_projectId, _name, _symbol, msg.sender);
    }

    
    function print(
        address _holder,
        uint256 _projectId,
        uint256 _amount,
        bool _preferUnstakedTickets
    ) external override onlyTerminal(_projectId) {
        // An amount must be specified.
        require(_amount > 0, "TicketBooth::print: NO_OP");

        // Get a reference to the project's ERC20 tickets.
        ITickets _tickets = ticketsOf[_projectId];

        // If there exists ERC-20 tickets and the caller prefers these unstaked tickets.
        bool _shouldUnstakeTickets = _preferUnstakedTickets &&
            _tickets != ITickets(address(0));

        if (_shouldUnstakeTickets) {
            // Print the equivalent amount of ERC20s.
            _tickets.print(_holder, _amount);
        } else {
            // Add to the staked balance and total supply.
            stakedBalanceOf[_holder][_projectId] =
                stakedBalanceOf[_holder][_projectId] +
                _amount;
            stakedTotalSupplyOf[_projectId] =
                stakedTotalSupplyOf[_projectId] +
                _amount;
        }

        emit Print(
            _holder,
            _projectId,
            _amount,
            _shouldUnstakeTickets,
            _preferUnstakedTickets,
            msg.sender
        );
    }

    
    function redeem(
        address _holder,
        uint256 _projectId,
        uint256 _amount,
        bool _preferUnstaked
    ) external override onlyTerminal(_projectId) {
        // Get a reference to the project's ERC20 tickets.
        ITickets _tickets = ticketsOf[_projectId];

        // Get a reference to the staked amount.
        uint256 _unlockedStakedBalance = stakedBalanceOf[_holder][_projectId] -
            lockedBalanceOf[_holder][_projectId];

        // Get a reference to the number of tickets there are.
        uint256 _unstakedBalanceOf = _tickets == ITickets(address(0))
            ? 0
            : _tickets.balanceOf(_holder);

        // There must be enough tickets.
        // Prevent potential overflow by not relying on addition.
        require(
            (_amount < _unstakedBalanceOf &&
                _amount < _unlockedStakedBalance) ||
                (_amount >= _unstakedBalanceOf &&
                    _unlockedStakedBalance >= _amount - _unstakedBalanceOf) ||
                (_amount >= _unlockedStakedBalance &&
                    _unstakedBalanceOf >= _amount - _unlockedStakedBalance),
            "TicketBooth::redeem: INSUFFICIENT_FUNDS"
        );

        // The amount of tickets to redeem.
        uint256 _unstakedTicketsToRedeem;

        // If there's no balance, redeem no tickets
        if (_unstakedBalanceOf == 0) {
            _unstakedTicketsToRedeem = 0;
            // If prefer converted, redeem tickets before redeeming staked tickets.
        } else if (_preferUnstaked) {
            _unstakedTicketsToRedeem = _unstakedBalanceOf >= _amount
                ? _amount
                : _unstakedBalanceOf;
            // Otherwise, redeem staked tickets before unstaked tickets.
        } else {
            _unstakedTicketsToRedeem = _unlockedStakedBalance >= _amount
                ? 0
                : _amount - _unlockedStakedBalance;
        }

        // The amount of staked tickets to redeem.
        uint256 _stakedTicketsToRedeem = _amount - _unstakedTicketsToRedeem;

        // Redeem the tickets.
        if (_unstakedTicketsToRedeem > 0)
            _tickets.redeem(_holder, _unstakedTicketsToRedeem);
        if (_stakedTicketsToRedeem > 0) {
            // Reduce the holders balance and the total supply.
            stakedBalanceOf[_holder][_projectId] =
                stakedBalanceOf[_holder][_projectId] -
                _stakedTicketsToRedeem;
            stakedTotalSupplyOf[_projectId] =
                stakedTotalSupplyOf[_projectId] -
                _stakedTicketsToRedeem;
        }

        emit Redeem(
            _holder,
            _projectId,
            _amount,
            _unlockedStakedBalance,
            _preferUnstaked,
            msg.sender
        );
    }

    
    function stake(
        address _holder,
        uint256 _projectId,
        uint256 _amount
    )
        external
        override
        requirePermissionAllowingWildcardDomain(
            _holder,
            _projectId,
            Operations.Stake
        )
    {
        // Get a reference to the project's ERC20 tickets.
        ITickets _tickets = ticketsOf[_projectId];

        // Tickets must have been issued.
        require(
            _tickets != ITickets(address(0)),
            "TicketBooth::stake: NOT_FOUND"
        );

        // Get a reference to the holder's current balance.
        uint256 _unstakedBalanceOf = _tickets.balanceOf(_holder);

        // There must be enough balance to stake.
        require(
            _unstakedBalanceOf >= _amount,
            "TicketBooth::stake: INSUFFICIENT_FUNDS"
        );

        // Redeem the equivalent amount of ERC20s.
        _tickets.redeem(_holder, _amount);

        // Add the staked amount from the holder's balance.
        stakedBalanceOf[_holder][_projectId] =
            stakedBalanceOf[_holder][_projectId] +
            _amount;

        // Add the staked amount from the project's total supply.
        stakedTotalSupplyOf[_projectId] =
            stakedTotalSupplyOf[_projectId] +
            _amount;

        emit Stake(_holder, _projectId, _amount, msg.sender);
    }

    
    function unstake(
        address _holder,
        uint256 _projectId,
        uint256 _amount
    )
        external
        override
        requirePermissionAllowingWildcardDomain(
            _holder,
            _projectId,
            Operations.Unstake
        )
    {
        // Get a reference to the project's ERC20 tickets.
        ITickets _tickets = ticketsOf[_projectId];

        // Tickets must have been issued.
        require(
            _tickets != ITickets(address(0)),
            "TicketBooth::unstake: NOT_FOUND"
        );

        // Get a reference to the amount of unstaked tickets.
        uint256 _unlockedStakedTickets = stakedBalanceOf[_holder][_projectId] -
            lockedBalanceOf[_holder][_projectId];

        // There must be enough unlocked staked tickets to unstake.
        require(
            _unlockedStakedTickets >= _amount,
            "TicketBooth::unstake: INSUFFICIENT_FUNDS"
        );

        // Subtract the unstaked amount from the holder's balance.
        stakedBalanceOf[_holder][_projectId] =
            stakedBalanceOf[_holder][_projectId] -
            _amount;

        // Subtract the unstaked amount from the project's total supply.
        stakedTotalSupplyOf[_projectId] =
            stakedTotalSupplyOf[_projectId] -
            _amount;

        // Print the equivalent amount of ERC20s.
        _tickets.print(_holder, _amount);

        emit Unstake(_holder, _projectId, _amount, msg.sender);
    }

    
    function lock(
        address _holder,
        uint256 _projectId,
        uint256 _amount
    )
        external
        override
        requirePermissionAllowingWildcardDomain(
            _holder,
            _projectId,
            Operations.Lock
        )
    {
        // Amount must be greater than 0.
        require(_amount > 0, "TicketBooth::lock: NO_OP");

        // The holder must have enough tickets to lock.
        require(
            stakedBalanceOf[_holder][_projectId] -
                lockedBalanceOf[_holder][_projectId] >=
                _amount,
            "TicketBooth::lock: INSUFFICIENT_FUNDS"
        );

        // Update the lock.
        lockedBalanceOf[_holder][_projectId] =
            lockedBalanceOf[_holder][_projectId] +
            _amount;
        lockedBalanceBy[msg.sender][_holder][_projectId] =
            lockedBalanceBy[msg.sender][_holder][_projectId] +
            _amount;

        emit Lock(_holder, _projectId, _amount, msg.sender);
    }

    
    function unlock(
        address _holder,
        uint256 _projectId,
        uint256 _amount
    ) external override {
        // Amount must be greater than 0.
        require(_amount > 0, "TicketBooth::unlock: NO_OP");

        // There must be enough locked tickets to unlock.
        require(
            lockedBalanceBy[msg.sender][_holder][_projectId] >= _amount,
            "TicketBooth::unlock: INSUFFICIENT_FUNDS"
        );

        // Update the lock.
        lockedBalanceOf[_holder][_projectId] =
            lockedBalanceOf[_holder][_projectId] -
            _amount;
        lockedBalanceBy[msg.sender][_holder][_projectId] =
            lockedBalanceBy[msg.sender][_holder][_projectId] -
            _amount;

        emit Unlock(_holder, _projectId, _amount, msg.sender);
    }

    
    function transfer(
        address _holder,
        uint256 _projectId,
        uint256 _amount,
        address _recipient
    )
        external
        override
        requirePermissionAllowingWildcardDomain(
            _holder,
            _projectId,
            Operations.Transfer
        )
    {
        // Can't transfer to the zero address.
        require(
            _recipient != address(0),
            "TicketBooth::transfer: ZERO_ADDRESS"
        );

        // An address can't transfer to itself.
        require(_holder != _recipient, "TicketBooth::transfer: IDENTITY");

        // There must be an amount to transfer.
        require(_amount > 0, "TicketBooth::transfer: NO_OP");

        // Get a reference to the amount of unlocked staked tickets.
        uint256 _unlockedStakedTickets = stakedBalanceOf[_holder][_projectId] -
            lockedBalanceOf[_holder][_projectId];

        // There must be enough unlocked staked tickets to transfer.
        require(
            _amount <= _unlockedStakedTickets,
            "TicketBooth::transfer: INSUFFICIENT_FUNDS"
        );

        // Subtract from the holder.
        stakedBalanceOf[_holder][_projectId] =
            stakedBalanceOf[_holder][_projectId] -
            _amount;

        // Add the tickets to the recipient.
        stakedBalanceOf[_recipient][_projectId] =
            stakedBalanceOf[_recipient][_projectId] +
            _amount;

        emit Transfer(_holder, _projectId, _recipient, _amount, msg.sender);
    }
}
