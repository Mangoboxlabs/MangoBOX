// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./../interfaces/ITerminalUtility.sol";

abstract contract TerminalUtility is ITerminalUtility {
    modifier onlyTerminal(uint256 _projectId) {
        require(
            address(terminalDirectory.terminalOf(_projectId)) == msg.sender,
            "TerminalUtility: UNAUTHORIZED"
        );
        _;
    }
    ITerminalDirectory public immutable override terminalDirectory;

   
    constructor(ITerminalDirectory _terminalDirectory) {
        terminalDirectory = _terminalDirectory;
    }
}
