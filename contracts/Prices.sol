// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IPrices.sol";


contract Prices is IPrices, Ownable {
    uint256 public constant override targetDecimals = 18;

    mapping(uint256 => uint256) public override feedDecimalAdjuster;

    mapping(uint256 => AggregatorV3Interface) public override feedFor;

    function getETHPriceFor(uint256 _currency) external view override returns (uint256) {
        if (_currency == 0) return 10**targetDecimals;

        AggregatorV3Interface _feed = feedFor[_currency];

        require(
            _feed != AggregatorV3Interface(address(0)),
            "Prices::getETHPrice: NOT_FOUND"
        );

         (, int256 _price, , , ) = _feed.latestRoundData();

        return uint256(_price) * feedDecimalAdjuster[_currency];
    }

    
    function addFeed(AggregatorV3Interface _feed, uint256 _currency) external override onlyOwner{
        require(_currency > 0, "Prices::addFeed: RESERVED");

        require(
            feedFor[_currency] == AggregatorV3Interface(address(0)),
            "Prices::addFeed: ALREADY_EXISTS"
        );

        uint256 _decimals = _feed.decimals();

        require(_decimals <= targetDecimals, "Prices::addFeed: BAD_DECIMALS");

        feedFor[_currency] = _feed;

       feedDecimalAdjuster[_currency] = 10**(targetDecimals - _decimals);

        emit AddFeed(_currency, _feed);
    }
}
