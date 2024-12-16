// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SelfHelp {
    struct SHG {
        address admin;
        string shgName;
        string shgDescription;
        uint256 timeOfCreation;
        uint256 balance;
        mapping(address => uint256) funderDetails;
        uint256 numberOfFunders;
        address[] funders;
        uint256 votingDuration;
    }

    enum ProposalStatus { Pending, Approved, Rejected }

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
        mapping(address => bool) votersInFavour;
        mapping(address => bool) votersAgainst;
    }

    uint256 public shgId = 0;
    uint256 public proposalId = 0;

    mapping(uint256 => SHG) public shgDetails;
    mapping(address => uint256[]) public memberOfShg;
    mapping(uint256 => uint256[]) public proposalIdInShg;
    mapping(uint256 => Proposal) public proposalDetails;

    modifier onlySHGMember(uint256 _shgId) {
        require(shgDetails[_shgId].funderDetails[msg.sender] > 0, "Not a member of this SHG");
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
        SHG storage shg = shgDetails[shgId];
        shg.admin = msg.sender;
        shg.shgName = _shgName;
        shg.shgDescription = _shgDescription;
        shg.timeOfCreation = block.timestamp;
        shg.balance = 0;
        shg.votingDuration = _votingDuration*3600;

        emit SHGCreated(shgId, msg.sender, _shgName);
    }

    function addFunds(uint256 _shgId) public payable {
        SHG storage shg = shgDetails[_shgId];
        require(msg.value > 0, "Must send funds");

        if (shg.funderDetails[msg.sender] == 0) {
            shg.funders.push(msg.sender);
            shg.numberOfFunders++;

            bool alreadyMember = false;
            for (uint256 i = 0; i < memberOfShg[msg.sender].length; i++) {
                if (memberOfShg[msg.sender][i] == _shgId) {
                    alreadyMember = true;
                    break;
                }
            }
            if (!alreadyMember) {
                memberOfShg[msg.sender].push(_shgId);
            }
        }

        shg.funderDetails[msg.sender] += msg.value;
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

    function voteInFavour(uint256 _proposalId) public {
        Proposal storage prop = proposalDetails[_proposalId];
        SHG storage shg = shgDetails[prop.shgId];
        require(shg.funderDetails[msg.sender] > 0, "Not a member of this SHG");
        require(block.timestamp <= prop.timeOfProposal + shg.votingDuration, "Voting period has ended");
        require(msg.sender != prop.proposer, "Proposer cannot vote");
        require(
            !prop.votersInFavour[msg.sender] && !prop.votersAgainst[msg.sender],
            "You have already voted"
        );

        prop.votersInFavour[msg.sender] = true;
        prop.votesInFavour++;

        emit Voted(_proposalId, msg.sender, true);
    }

    function voteAgainst(uint256 _proposalId) public {
        Proposal storage prop = proposalDetails[_proposalId];
        SHG storage shg = shgDetails[prop.shgId];
        require(shg.funderDetails[msg.sender] > 0, "Not a member of this SHG");
        require(block.timestamp <= prop.timeOfProposal + shg.votingDuration, "Voting period has ended");
        require(msg.sender != prop.proposer, "Proposer cannot vote");
        require(
            !prop.votersInFavour[msg.sender] && !prop.votersAgainst[msg.sender],
            "You have already voted"
        );

        prop.votersAgainst[msg.sender] = true;
        prop.votesAgainst++;

        emit Voted(_proposalId, msg.sender, false);
    }

    function finalizeProposal(uint256 _proposalId) public {
        Proposal storage prop = proposalDetails[_proposalId];
        SHG storage shg = shgDetails[prop.shgId];
        require(block.timestamp > prop.timeOfProposal + shg.votingDuration, "Voting still in progress");
        require(prop.status == ProposalStatus.Pending, "Proposal already finalized");

        if (prop.votesInFavour > prop.votesAgainst) {
            prop.status = ProposalStatus.Approved;
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

        (bool success, ) = payable(msg.sender).call{value: amountToTransfer}("");
        require(success, "Transfer failed");

        emit FundsClaimed(_shgId, _proposalId, msg.sender, amountToTransfer);
    }

    function getFunderDetails(uint256 _shgId, address _funder) public view returns (uint256) {
        return shgDetails[_shgId].funderDetails[_funder];
    }

    function getProposalVoterDetails(uint256 _proposalId, address _voter)
        public
        view
        returns (bool inFavour, bool against)
    {
        Proposal storage prop = proposalDetails[_proposalId];
        return (prop.votersInFavour[_voter], prop.votersAgainst[_voter]);
    }
}
