// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SelfHelp {
    struct SHG {
        address admin;
        string shgName;
        string shgDescription;
        uint256 timeOfCreation;
        uint256 balance;
        mapping(address => bool) funders;
        uint256 votingDuration;
    }

    enum ProposalStatus { Pending, Approved, Rejected, Expired }

    struct Proposal {
        uint256 shgId;
        address proposer;
        string proposalName;
        string proposalDescription;
        uint256 amount;
        uint256 votesInFavour;
        uint256 votesAgainst;
        uint256 timeOfProposal;
        ProposalStatus status;
    }

    uint256 public shgId = 0;
    uint256 public proposalId = 0;

    mapping(uint256 => SHG) public shgDetails;
    mapping(uint256 => Proposal) public proposalDetails;
    mapping(uint256 => address[]) public members;
    mapping(address => uint256[]) public memberOfShg;
    mapping(uint256 => uint256[]) public proposalIdInShg;

    modifier onlySHGMember(uint256 _shgId) {
        require(shgDetails[_shgId].funders[msg.sender], "Not a member of this SHG");
        _;
    }

    modifier onlySHGAdmin(uint256 _shgId) {
        require(msg.sender == shgDetails[_shgId].admin, "Only SHG admin can perform this action");
        _;
    }

    event SHGCreated(uint256 indexed shgId, address indexed admin, string name);
    event FundsAdded(uint256 indexed shgId, address indexed funder, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, uint256 indexed shgId, address indexed proposer, string name);
    event Voted(uint256 indexed proposalId, address indexed voter, bool inFavour);
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);
    event FundsClaimed(uint256 indexed shgId, uint256 indexed proposalId, address indexed proposer, uint256 amount);

    function addSHG(string memory _shgName, string memory _shgDescription, uint256 _votingDuration) public {
        shgId++;
        require(memberOfShg[msg.sender].length == 0, "You can only create one SHG");
        
        SHG storage newShg = shgDetails[shgId];
        newShg.admin = msg.sender;
        newShg.shgName = _shgName;
        newShg.shgDescription = _shgDescription;
        newShg.timeOfCreation = block.timestamp;
        newShg.balance = 0;
        newShg.votingDuration = _votingDuration * 1 hours;

        memberOfShg[msg.sender].push(shgId);
        members[shgId].push(msg.sender);
        
        emit SHGCreated(shgId, msg.sender, _shgName);
    }

    function addFunds(uint256 _shgId) public payable {
        require(msg.value > 0, "Must send funds");
        SHG storage shg = shgDetails[_shgId];
        
        if (!shg.funders[msg.sender]) {
            shg.funders[msg.sender] = true;
            members[_shgId].push(msg.sender);
            memberOfShg[msg.sender].push(_shgId);
        }

        shg.balance += msg.value;
        emit FundsAdded(_shgId, msg.sender, msg.value);
    }

    function createProposal(
        uint256 _shgId,
        string memory _proposalName,
        string memory _proposalDescription,
        uint256 _amount
    ) public onlySHGMember(_shgId) {
        require(_amount <= shgDetails[_shgId].balance, "Insufficient SHG balance");

        proposalId++;
        proposalIdInShg[_shgId].push(proposalId);

        Proposal storage prop = proposalDetails[proposalId];
        prop.shgId = _shgId;
        prop.proposer = msg.sender;
        prop.proposalName = _proposalName;
        prop.proposalDescription = _proposalDescription;
        prop.amount = _amount;
        prop.timeOfProposal = block.timestamp;
        prop.status = ProposalStatus.Pending;

        emit ProposalCreated(proposalId, _shgId, msg.sender, _proposalName);
    }

    function vote(uint256 _proposalId, bool _inFavour) public {
        Proposal storage prop = proposalDetails[_proposalId];
        SHG storage shg = shgDetails[prop.shgId];
        require(shg.funders[msg.sender], "Not a member of this SHG");
        require(block.timestamp <= prop.timeOfProposal + shg.votingDuration, "Voting period has ended");
        require(msg.sender != prop.proposer, "Proposer cannot vote");

        if (_inFavour) {
            prop.votesInFavour++;
        } else {
            prop.votesAgainst++;
        }

        emit Voted(_proposalId, msg.sender, _inFavour);
    }

    function finalizeProposal(uint256 _proposalId) public {
        Proposal storage prop = proposalDetails[_proposalId];
        SHG storage shg = shgDetails[prop.shgId];
        require(block.timestamp > prop.timeOfProposal + shg.votingDuration, "Voting still in progress");
        require(prop.status == ProposalStatus.Pending, "Proposal already finalized");

        uint256 totalMembers = members[prop.shgId].length;
        uint256 requiredVotes = (totalMembers * 50) / 100; // Minimum 50% of members must vote

        if (prop.votesInFavour > prop.votesAgainst && (prop.votesInFavour + prop.votesAgainst) >= requiredVotes) {
            prop.status = ProposalStatus.Approved;
        } else if ((prop.votesInFavour + prop.votesAgainst) < requiredVotes) {
            prop.status = ProposalStatus.Expired;
        } else {
            prop.status = ProposalStatus.Rejected;
        }

        emit ProposalFinalized(_proposalId, prop.status);
    }

    function claimFund(uint256 _shgId, uint256 _proposalId) public {
        Proposal storage prop = proposalDetails[_proposalId];
        SHG storage shg = shgDetails[_shgId];

        require(msg.sender == prop.proposer, "Only proposer can claim funds");
        require(prop.status == ProposalStatus.Approved, "Proposal not approved");
        require(prop.amount <= shg.balance, "Insufficient SHG balance");

        uint256 amountToTransfer = prop.amount;
        prop.amount = 0;
        shg.balance -= amountToTransfer;
        payable(msg.sender).transfer(amountToTransfer);

        emit FundsClaimed(_shgId, _proposalId, msg.sender, amountToTransfer);
    }
}
