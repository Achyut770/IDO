// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IDO is ReentrancyGuard, Ownable {
    struct Project {
        uint256 totalSupply;
        uint256 rate;
        uint256 voteCount;
        address owner;
        address tokenAddress;
        address shouldBePaidInThisToken;
        bool acceptingETH;
    }

    mapping(address => mapping(uint => mapping(address => bool)))
        private hasVotedForProject;

    mapping(address => Project[]) public projectsByOwner;
    mapping(address => bool) private AlreadyInTheAddressArray;
    address[] private AddressArray;

    error ZeroTotalSupply();
    error ZeroRate();
    error ZeroTokenAddress();
    error ZeroTokenToBePaidAddress();
    error TotalSupplyNotMultipleOfRate();
    error TarnsferAmountFailed();

    // events

    event AddingTokenForEth(
        address indexed owner,
        uint indexed amount,
        address indexed tokenAddress
    );
    event AddingTokenForToken(
        address indexed owner,
        uint indexed amount,
        address indexed tokenAddress,
        address shouldBePaidInThisToken
    );
    event BuyingTokenForEth(
        address indexed owner,
        address indexed buyer,
        uint indexed projectIndex,
        uint amount
    );
    event BuyingTokenForToken(
        address indexed owner,
        address buyer,
        uint indexed amount,
        address indexed tokenAddress,
        address shouldBePaidInThisToken
    );

    modifier initialSatisfy(
        uint256 rate,
        address _tokenAddress,
        uint256 _totalSupply,
        address _shouldBePaidInThisToken,
        bool _acceptingETH
    ) {
        if (_totalSupply < 0) revert ZeroTotalSupply();
        if (rate < 0) revert ZeroRate();
        if (_tokenAddress == address(0)) revert ZeroTokenAddress();
        if (!_acceptingETH) {
            if (_shouldBePaidInThisToken == address(0))
                revert ZeroTokenToBePaidAddress();
        }
        if (_totalSupply % rate != 0) revert TotalSupplyNotMultipleOfRate();
        _;
    }

    // View Functions

    function getProjectCount(address owner) external view returns (uint256) {
        return projectsByOwner[owner].length;
    }

    function getProjectDetails(
        address owner,
        uint256 projectIndex
    )
        external
        view
        returns (uint256, uint256, address, address, bool, uint256)
    {
        Project storage project = projectsByOwner[owner][projectIndex];
        return (
            project.totalSupply,
            project.rate,
            project.tokenAddress,
            project.shouldBePaidInThisToken,
            project.acceptingETH,
            project.voteCount
        );
    }

    function getProjectsByOwner(
        address owner
    ) external view returns (Project[] memory projectArray) {
        uint projectLength = projectsByOwner[owner].length;
        projectArray = new Project[](projectLength);
        for (uint i = 0; i < projectLength; unchecked_inc(i)) {
            projectArray[i] = projectsByOwner[owner][i];
        }
    }

    function getAddresses()
        external
        view
        returns (address[] memory addressArray)
    {
        uint addressLength = AddressArray.length;
        addressArray = new address[](addressLength);
        for (uint i = 0; i < addressLength; unchecked_inc(i)) {
            addressArray[i] = AddressArray[i];
        }
    }

    function AddTokenToTheContract(
        address owner,
        uint projectIndex,
        uint amount
    ) external {
        if (amount == 0) {
            revert ZeroTotalSupply();
        }
        Project storage project = projectsByOwner[owner][projectIndex];
        IERC20(project.tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        project.totalSupply += amount;
    }

    // Main interacting Functions

    function addProject(
        uint256 _totalSupply,
        uint256 _rate,
        address _tokenAddress,
        address _shouldBePaidInThisToken,
        bool _acceptingETH
    ) private {
        if (!AlreadyInTheAddressArray[msg.sender]) {
            AddressArray.push(msg.sender);
            AlreadyInTheAddressArray[msg.sender] = true;
        }
        IERC20(_tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _totalSupply
        );
        Project memory project;
        project.owner = msg.sender;
        project.totalSupply = _totalSupply;
        project.rate = _rate;
        project.tokenAddress = _tokenAddress;
        project.acceptingETH = _acceptingETH;
        project.shouldBePaidInThisToken = _shouldBePaidInThisToken;
        projectsByOwner[msg.sender].push(project);
    }

    function putProjectForETH(
        uint256 rate,
        address tokenAddress,
        uint256 totalSupply
    )
        external
        initialSatisfy(rate, tokenAddress, totalSupply, address(0), true)
    {
        emit AddingTokenForEth(msg.sender, totalSupply, tokenAddress);
        addProject(totalSupply, rate, tokenAddress, address(0), true);
    }

    function putProjectForToken(
        uint256 _rate,
        address _tokenAddress,
        uint256 _totalSupply,
        address _shouldBePaidInThisToken
    )
        external
        initialSatisfy(
            _rate,
            _tokenAddress,
            _totalSupply,
            _shouldBePaidInThisToken,
            false
        )
    {
        emit AddingTokenForToken(
            msg.sender,
            _totalSupply,
            _tokenAddress,
            _shouldBePaidInThisToken
        );
        addProject(
            _totalSupply,
            _rate,
            _tokenAddress,
            _shouldBePaidInThisToken,
            false
        );
    }

    function buyToken(
        address owner,
        uint256 projectIndex,
        uint amount
    ) external payable nonReentrant {
        Project storage project = projectsByOwner[owner][projectIndex];
        uint amountOut;
        uint amountToSendTheOwner;
        if (project.acceptingETH) {
            amountOut = project.rate * msg.value;
            amountToSendTheOwner = msg.value - (3 * msg.value) / 1000;
            emit BuyingTokenForEth(owner, msg.sender, projectIndex, amountOut);

            (bool sent, bytes memory data) = project.owner.call{
                value: amountToSendTheOwner
            }("");
            if (!sent) {
                revert TarnsferAmountFailed();
            }
        } else {
            amountOut = project.rate * amount;
            emit BuyingTokenForToken(
                owner,
                msg.sender,
                amount,
                project.tokenAddress,
                project.shouldBePaidInThisToken
            );
            amountToSendTheOwner = amount - (3 * amount) / 1000;
            IERC20(project.shouldBePaidInThisToken).transferFrom(
                msg.sender,
                project.owner,
                amountToSendTheOwner
            );
        }
        IERC20(project.tokenAddress).transfer(msg.sender, amountOut);
    }

    function voteForProject(address owner, uint256 projectIndex) external {
        Project storage project = projectsByOwner[owner][projectIndex];

        bool hasVoted = hasVotedForProject[owner][projectIndex][msg.sender];
        if (hasVoted) {
            hasVotedForProject[owner][projectIndex][msg.sender] = false;
            project.voteCount--;
        } else {
            hasVotedForProject[owner][projectIndex][msg.sender] = true;
            project.voteCount++;
        }
    }

    // Taking ether and token from the contract

    function getEth(uint amount) external onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    function getToken(uint amount, address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    function changeRateOfProject(
        address owner,
        uint projectIndex,
        uint newRate
    ) external {
        projectsByOwner[owner][projectIndex].rate = newRate;
    }

    // Pure Functions

    function unchecked_inc(uint i) internal pure returns (uint) {
        unchecked {
            i++;
        }
        return i;
    }
}
