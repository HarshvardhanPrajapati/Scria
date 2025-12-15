methods {
    function transfer(address recipient, uint256 amount) returns (bool success);
}

rule transfer_cannot_exceed_sender_balance {
    method transfer(address recipient, uint256 amount) returns (bool success);

    env e;

    uint256 senderBalance_pre = balanceOf[e.msg.sender];

    call transfer(e, e.msg.sender, recipient, amount);

    assert (success => senderBalance_pre >= amount);
}