//SPDX-License-Identifier: MIT

pragma solidity ^0.7.4;

interface BEP20 {
    function balanceOf(address) external returns (uint);
    function transferFrom(address, address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
}