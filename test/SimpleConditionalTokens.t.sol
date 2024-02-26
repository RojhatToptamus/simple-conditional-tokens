// forge test --match-path test/SimpleConditionalTokens.t.sol -vvvv
// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity ^0.8.0;
import "forge-std/console.sol";
import {Test, StdCheats, console} from "forge-std/Test.sol";
// use interface since the actual contract version is not compitable with the current solidity version
import {IConditionalTokens} from "./interface/IConditionalTokens.sol";
import {CTHelpers} from "./utils/CTHelpers.sol";
import {IERC20} from "./interface/IERC20.sol";

contract SimpleConditionalTokensTest is Test {
    // Contracts
    IConditionalTokens public conditionalTokens;
    IERC20 public collateralToken;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted upon the successful preparation of a condition.
    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount
    );
    /// @dev Emitted upon the successful payout report.
    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount,
        uint[] payoutNumerators
    );
    /// @dev Emitted when a position is successfully split.
    event PositionSplit(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed conditionId,
        uint amount
    );
    /// @dev Emitted when positions are successfully merged.
    event PositionsMerge(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed conditionId,
        uint amount
    );
    /// @dev Emitted when positions are successfully redeemed.
    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 conditionId,
        uint payout
    );

    /*//////////////////////////////////////////////////////////////
                                VARIABLES   
    //////////////////////////////////////////////////////////////*/
    address public Alice = address(1);
    address public Bob = address(2);
    address public Carla = address(3);
    address public oracle = address(999999);

    function setUp() public {
        conditionalTokens = IConditionalTokens(
            deployCode("SimpleConditionalTokens.sol")
        );
        // deploy collateral token
        collateralToken = IERC20(deployCode("MintableERC20.sol"));
    }

    function test_AssertContractsDeployed() public {
        assertTrue(
            address(conditionalTokens) != address(0),
            "Simple Conditional Tokens contract not deployed"
        );
        assertTrue(
            address(collateralToken) != address(0),
            "Mock Coin contract not deployed"
        );
    }

    function test_SplitPosition() public {
        // Prepare a new  condition using the helper function
        address signer = Alice;
        bytes32 questionId = keccak256(abi.encode("Will BTC price go up?"));
        uint256 outcomeSlotCount = 2;
        prepareCondition(
            signer, // random signer
            questionId, // random question id
            outcomeSlotCount
        );
        // Split position using the helper function
        uint256 amount = 100 ether;
        splitPosition(signer, amount, questionId, outcomeSlotCount);
    }

    function test_MergePositions() public {
        // Prepare a new  condition using the helper function
        address signer = Bob;
        bytes32 questionId = keccak256(abi.encode("Will BTC price go up?"));
        uint256 outcomeSlotCount = 2;

        prepareCondition(
            signer, // random signer
            questionId, // random question id
            2
        );
        // Split position using the helper function
        uint256 amountToSplit = 100 ether;
        splitPosition(signer, amountToSplit, questionId, outcomeSlotCount);
        // Merge positions using the helper function
        uint256 amountToMerge = 10 ether;
        mergePositions(signer, amountToMerge, questionId);
    }

    function test_ReportPayouts() public {
        // Prepare a new  condition using the helper function
        address signer = Carla;
        bytes32 questionId = keccak256(abi.encode("Will ETH price go up?"));
        prepareCondition(
            signer, // random signer
            questionId, // random question id
            2
        );

        bytes32 conditionId = CTHelpers.getConditionId(oracle, questionId, 2);

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        // oracle reports the payouts
        vm.startPrank(oracle);

        vm.expectEmit();

        emit ConditionResolution(conditionId, oracle, questionId, 2, payouts);

        conditionalTokens.reportPayouts(questionId, payouts);

        for (uint i = 0; i < payouts.length; i++) {
            uint256 payoutNumerator = conditionalTokens.payoutNumerators(
                conditionId,
                i
            );
            assertTrue(
                payoutNumerator == payouts[i],
                "Payouts not reported successfully"
            );
        }
    }

    function test_RedeemPosition() public {
        // Prepare a new  condition using the helper function
        address signer = Alice;
        address investor1 = Bob;
        address investor2 = Carla;
        uint256 outcomeSlotCount = 2;
        address[2] memory investors = [investor1, investor2];

        uint256[] memory investors_token0_balances = new uint256[](2);
        uint256[] memory investors_token1_balances = new uint256[](2);
        uint256[] memory investors_collateral_balances = new uint256[](2);
        uint256[] memory investors_payouts = new uint256[](2);

        bytes32 questionId = keccak256(abi.encode("Will Matic price go up?"));
        prepareCondition(signer, questionId, 2);
        // investors split positions
        for (uint i = 0; i < investors.length; i++) {
            uint256 amount = 100 ether;
            // investor splits position and gets 100 tokens for each outcome
            splitPosition(investors[i], amount, questionId, outcomeSlotCount);
        }

        // Payouts are reported
        bytes32 conditionId = CTHelpers.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );

        // outcome 0 wins
        uint256[] memory payoutNumerators = new uint256[](2);
        payoutNumerators[0] = 1;
        payoutNumerators[1] = 0;
        // oracle reports the payouts
        vm.prank(oracle);
        conditionalTokens.reportPayouts(questionId, payoutNumerators);

        // Fetch minted ERC1155 position IDs
        uint[] memory positionIds = new uint[](2);

        for (uint i = 0; i < 2; i++) {
            positionIds[i] = CTHelpers.getPositionId(
                collateralToken,
                CTHelpers.getCollectionId(bytes32(i), conditionId, i)
            );
        }
        // fetch payoutDenominator and calculate investor1's payout for both tokens
        uint256 payoutDenominator = conditionalTokens.payoutDenominator(
            conditionId
        );
        console.log("payoutDenominator: %s", payoutDenominator);
        // get investors token balances before redemption
        for (uint i = 0; i < investors.length; i++) {
            investors_token0_balances[i] = conditionalTokens.balanceOf(
                investors[i],
                positionIds[0]
            );
            investors_token1_balances[i] = conditionalTokens.balanceOf(
                investors[i],
                positionIds[1]
            );
            investors_collateral_balances[i] = collateralToken.balanceOf(
                investors[i]
            );
        }
        // calculate investor's  payouts for both tokens
        for (uint i = 0; i < investors.length; i++) {
            investors_payouts[i] =
                ((investors_token0_balances[i] * payoutNumerators[0]) /
                    payoutDenominator) +
                ((investors_token1_balances[i] * payoutNumerators[1]) /
                    payoutDenominator);
        }
        // investors redeem positions
        for (uint i = 0; i < investors.length; i++) {
            vm.startPrank(investors[i]);
            vm.expectEmit();
            emit PayoutRedemption(
                investors[i],
                IERC20(collateralToken),
                conditionId,
                investors_payouts[i]
            );
            conditionalTokens.redeemPositions(
                IERC20(collateralToken),
                conditionId
            );
            vm.stopPrank();
            assertTrue(
                conditionalTokens.balanceOf(investors[i], positionIds[0]) == 0,
                "Token 0 not redeemed successfully"
            );
            assertTrue(
                conditionalTokens.balanceOf(investors[i], positionIds[1]) == 0,
                "Token 1 not redeemed successfully"
            );
            assertTrue(
                collateralToken.balanceOf(investors[i]) ==
                    investors_collateral_balances[i] + investors_payouts[i],
                "Collateral not redeemed successfully"
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZING TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_PrepareCondition(
        address _signer,
        uint256 _questionId,
        uint _outcomeSlotCount
    ) public {
        vm.assume(_outcomeSlotCount > 1 && _outcomeSlotCount <= 256);
        vm.assume(_questionId != 0);
        vm.assume(_signer != address(0));

        //random question id
        bytes32 questionId = keccak256(abi.encode(_questionId));

        prepareCondition(address(_signer), questionId, _outcomeSlotCount);
    }

    /*//////////////////////////////////////////////////////////////
                               FAIL CASES
    //////////////////////////////////////////////////////////////*/

    function test_NotReportPayouts() public {
        // Prepare a new  condition using the helper function
        address signer = Carla;
        bytes32 questionId = keccak256(abi.encode("Will ETH price go up?"));
        bytes32 unpreparedQuestionId = keccak256(
            abi.encode("Will stock market go up?")
        );
        prepareCondition(
            signer, // random signer
            questionId, // random question id
            2
        );
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;

        uint256[] memory zeroPayouts = new uint256[](2);
        zeroPayouts[0] = 0;
        zeroPayouts[1] = 0;

        // should not allow reporting by incorrect oracle
        address notOracle = address(0);
        vm.expectRevert("condition not prepared or found");
        vm.prank(notOracle);
        conditionalTokens.reportPayouts(questionId, payouts);

        // should not allow report with wrong questionId
        vm.expectRevert("condition not prepared or found");
        vm.prank(oracle);
        conditionalTokens.reportPayouts(unpreparedQuestionId, payouts);

        //should not allow report with zero payouts in all slots
        vm.expectRevert("payout is all zeroes");
        vm.prank(oracle);
        conditionalTokens.reportPayouts(questionId, zeroPayouts);
    }

    function test_NotSplitPosition() public {
        // Prepare a new  condition using the helper function
        address signer = Alice;
        bytes32 questionId = keccak256(abi.encode("Will BTC price go up?"));
        uint256 outcomeSlotCount = 2;
        uint256 amount = 100 ether;

        bytes32 conditionId = CTHelpers.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );

        // should not allow split position without preparing condition
        vm.startPrank(signer);
        vm.expectRevert("condition not prepared yet");
        conditionalTokens.splitPosition(
            IERC20(collateralToken),
            conditionId,
            amount
        );
        vm.stopPrank();

        // should not allow split position wiithout collateral token approval
        vm.startPrank(signer);
        conditionalTokens.prepareCondition(
            oracle,
            questionId,
            outcomeSlotCount
        );
        vm.expectRevert("Insufficient balance");
        conditionalTokens.splitPosition(
            IERC20(collateralToken),
            conditionId,
            amount
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function prepareCondition(
        address signer,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) public returns (bool) {
        vm.startPrank(signer);

        bytes32 conditionId = CTHelpers.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );

        vm.expectEmit();

        emit ConditionPreparation(
            conditionId,
            oracle,
            questionId,
            outcomeSlotCount
        );

        conditionalTokens.prepareCondition(
            oracle,
            questionId,
            outcomeSlotCount
        );

        //should make outcome slot count available via getOutcomeSlotCount
        uint256 fetchedOutcomeSlotCount = conditionalTokens.getOutcomeSlotCount(
            conditionId
        );
        assertTrue(
            fetchedOutcomeSlotCount == outcomeSlotCount,
            "Outcome slot count not available"
        );

        //should leave payout denominator unset
        uint256 payoutDenominator = conditionalTokens.payoutDenominator(
            conditionId
        );
        assertTrue(payoutDenominator == 0, "Payout denominator not unset");

        // should not be able to prepare the same condition more than once
        vm.expectRevert("condition already prepared");
        conditionalTokens.prepareCondition(
            oracle,
            questionId,
            outcomeSlotCount
        );
        vm.stopPrank();
        return true;
    }

    function splitPosition(
        address signer,
        uint256 amount,
        bytes32 questionId,
        uint256 outcomeSlotCount // outcomeSlotCount = 2 for binary markets
    ) public returns (bool) {
        bytes32 conditionId = CTHelpers.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );

        // check if condition is prepared
        // zero if condition has not been prepared yet.
        uint256 fetchedOutcomeSlotCount = conditionalTokens.getOutcomeSlotCount(
            conditionId
        );
        assertTrue(
            fetchedOutcomeSlotCount == outcomeSlotCount,
            "condition not prepared, prepare condition first"
        );

        // Mint collateral token to Signer address and approve the contract
        vm.startPrank(signer);
        collateralToken.mint(signer, amount);
        assertTrue(
            collateralToken.balanceOf(signer) == amount,
            "Collateral token not minted to signer"
        );
        collateralToken.approve(address(conditionalTokens), amount);

        vm.expectEmit();
        emit PositionSplit(
            signer,
            IERC20(collateralToken),
            conditionId,
            amount
        );

        // Split position
        conditionalTokens.splitPosition(
            IERC20(collateralToken),
            conditionId,
            amount
        );

        // Fetch minted ERC1155 position IDs
        uint[] memory positionIds = new uint[](2);

        positionIds[0] = CTHelpers.getPositionId(
            collateralToken,
            CTHelpers.getCollectionId(bytes32(0), conditionId, 0)
        );
        positionIds[1] = CTHelpers.getPositionId(
            collateralToken,
            CTHelpers.getCollectionId(bytes32(0), conditionId, 1)
        );

        // Assertions to verify the split operation
        assertTrue(
            conditionalTokens.balanceOf(signer, positionIds[0]) == amount,
            "token 0 not minted successfully"
        );
        assertTrue(
            conditionalTokens.balanceOf(signer, positionIds[1]) == amount,
            "token 1 not minted successfully"
        );
        vm.stopPrank();
        return true;
    }

    function mergePositions(
        address signer,
        uint256 amount,
        bytes32 questionId
    ) public {
        vm.startPrank(signer);
        // outcomeSlotCount = 2 for binary markets
        uint256 outcomeSlotCount = 2;

        bytes32 conditionId = CTHelpers.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );

        // check if condition is prepared
        // zero if condition has not been prepared yet.
        uint256 fetchedOutcomeSlotCount = conditionalTokens.getOutcomeSlotCount(
            conditionId
        );
        assertTrue(
            fetchedOutcomeSlotCount == outcomeSlotCount,
            "condition not prepared, prepare condition first"
        );

        // get erc1155 position ids
        uint256[] memory positionIds = new uint[](2);
        positionIds[0] = CTHelpers.getPositionId(
            collateralToken,
            CTHelpers.getCollectionId(bytes32(0), conditionId, 0)
        );

        positionIds[1] = CTHelpers.getPositionId(
            collateralToken,
            CTHelpers.getCollectionId(bytes32(0), conditionId, 1)
        );
        // save balances before merge
        uint256 position0BalanceBeforeMerge = conditionalTokens.balanceOf(
            signer,
            positionIds[0]
        );
        uint256 position1BalanceBeforeMerge = conditionalTokens.balanceOf(
            signer,
            positionIds[1]
        );
        uint256 collateralBalanceBeforeMerge = collateralToken.balanceOf(
            signer
        );

        vm.expectEmit();
        emit PositionsMerge(
            signer,
            IERC20(collateralToken),
            conditionId,
            amount
        );

        // Merge position
        conditionalTokens.mergePositions(
            IERC20(collateralToken),
            conditionId,
            amount
        );
        // get balances after merge
        uint256 position0BalanceAfterMerge = conditionalTokens.balanceOf(
            signer,
            positionIds[0]
        );
        uint256 position1BalanceAfterMerge = conditionalTokens.balanceOf(
            signer,
            positionIds[1]
        );

        uint256 collateralBalanceAfterMerge = collateralToken.balanceOf(signer);

        // Assertions: check collateral and position balances
        assertTrue(
            collateralBalanceAfterMerge ==
                collateralBalanceBeforeMerge + amount,
            "Collateral token not transferred to signer"
        );
        assertTrue(
            position0BalanceAfterMerge == position0BalanceBeforeMerge - amount,
            "Token 0 not burned successfully"
        );
        assertTrue(
            position1BalanceAfterMerge == position1BalanceBeforeMerge - amount,
            "Token 1 not burned successfully"
        );
        vm.stopPrank();
    }
}
