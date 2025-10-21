pragma solidity ^0.8.0;

contract BallGame {

    uint8 public ballPosition;

    constructor() {
        ballPosition = 1;
    }
    
    function pass() external {
        if (ballPosition == 1)
            ballPosition = 3;
        else if (ballPosition == 3)
            ballPosition = 1;
        else
            ballPosition = 2;
    }

}