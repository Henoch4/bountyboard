// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title BountyBoard — winner-takes-all bounties (NodeWorks handles claimed
/// jobs; this handles open competition). Poster locks the reward, hunters
/// submit, poster awards a submitter. Unawarded past deadline → poster reclaims.
contract BountyBoard is ReentrancyGuard, Ownable {
    struct Submission {
        address hunter;
        string resultURI;
    }

    struct Bounty {
        address poster;
        uint256 reward;
        uint64 deadline;
        string specURI;
        bool awarded;
        address winner;
        Submission[] subs;
    }

    Bounty[] private _bounties;

    event Posted(uint256 indexed id, address indexed poster, uint256 reward, uint64 deadline);
    event Submitted(uint256 indexed id, address indexed hunter);
    event Awarded(uint256 indexed id, address indexed winner, uint256 reward);
    event Reclaimed(uint256 indexed id, uint256 reward);

    constructor() Ownable(msg.sender) {}

    function post(string calldata specURI, uint64 deadlineHours) external payable nonReentrant returns (uint256) {
        require(bytes(specURI).length > 0, "Empty spec");
        require(msg.value > 0, "Bad reward");
        require(deadlineHours > 0, "Bad deadline");
        _bounties.push();
        Bounty storage b = _bounties[_bounties.length - 1];
        b.poster = msg.sender;
        b.reward = msg.value;
        b.deadline = uint64(block.timestamp) + deadlineHours * 3600;
        b.specURI = specURI;
        uint256 id = _bounties.length - 1;
        emit Posted(id, msg.sender, msg.value, b.deadline);
        return id;
    }

    function submit(uint256 id, string calldata resultURI) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(!b.awarded, "Awarded");
        require(block.timestamp < b.deadline, "Past deadline");
        require(bytes(resultURI).length > 0, "Empty result");
        b.subs.push(Submission(msg.sender, resultURI));
        emit Submitted(id, msg.sender);
    }

    function award(uint256 id, address winner) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(msg.sender == b.poster, "Not poster");
        require(!b.awarded, "Awarded");
        bool found = false;
        for (uint256 i = 0; i < b.subs.length; i++) {
            if (b.subs[i].hunter == winner) { found = true; break; }
        }
        require(found, "Winner never submitted");
        b.awarded = true;
        b.winner = winner;
        (bool ok, ) = winner.call{value: b.reward}("");
        require(ok, "Pay failed");
        emit Awarded(id, winner, b.reward);
    }

    function reclaim(uint256 id) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(msg.sender == b.poster, "Not poster");
        require(!b.awarded, "Awarded");
        require(block.timestamp >= b.deadline, "Not expired");
        b.awarded = true; // closes the bounty without a winner
        (bool ok, ) = b.poster.call{value: b.reward}("");
        require(ok, "Pay failed");
        emit Reclaimed(id, b.reward);
    }

    function totalBounties() external view returns (uint256) {
        return _bounties.length;
    }

    function getBounty(uint256 id)
        external
        view
        returns (address poster, uint256 reward, uint64 deadline, string memory specURI, bool awarded, address winner, uint256 subCount)
    {
        Bounty storage b = _bounties[id];
        return (b.poster, b.reward, b.deadline, b.specURI, b.awarded, b.winner, b.subs.length);
    }

    function submission(uint256 id, uint256 idx) external view returns (address hunter, string memory resultURI) {
        Submission storage s = _bounties[id].subs[idx];
        return (s.hunter, s.resultURI);
    }
}
