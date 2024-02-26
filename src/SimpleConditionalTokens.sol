pragma solidity ^0.5.1;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "./ERC1155/ERC1155.sol";
import {CTHelpers} from "./CTHelpers.sol";

contract SimpleConditionalTokens is ERC1155 {
    /// @dev Emitted upon the successful preparation of a condition.
    /// @param conditionId The condition's ID. This ID may be derived from the other three parameters via ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
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
    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 conditionId,
        uint payout
    );

    /// Mapping key is an condition ID. Value represents numerators of the payout vector associated with the condition. This array is initialized with a length equal to the outcome slot count. E.g. Condition with 3 outcomes [A, B, C] and two of those correct [0.5, 0.5, 0]. In Ethereum there are no decimal values, so here, 0.5 is represented by fractions like 1/2 == 0.5. That's why we need numerator and denominator values. Payout numerators are also used as a check of initialization. If the numerators array is empty (has length zero), the condition was not created/prepared. See getOutcomeSlotCount.
    mapping(bytes32 => uint[]) public payoutNumerators;
    /// Denominator is also used for checking if the condition has been resolved. If the denominator is non-zero, then the condition has been resolved.
    mapping(bytes32 => uint) public payoutDenominator;

    /// @dev This function prepares a condition by initializing a payout vector associated with the condition.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    function prepareCondition(
        address oracle,
        bytes32 questionId,
        uint outcomeSlotCount
    ) external {
        // Limit of 256 because we use a partition array that is a number of 256 bits.
        require(outcomeSlotCount <= 256, "too many outcome slots");
        require(
            outcomeSlotCount > 1,
            "there should be more than one outcome slot"
        );
        bytes32 conditionId = CTHelpers.getConditionId(
            oracle,
            questionId,
            outcomeSlotCount
        );
        require(
            payoutNumerators[conditionId].length == 0,
            "condition already prepared"
        );
        payoutNumerators[conditionId] = new uint[](outcomeSlotCount);
        emit ConditionPreparation(
            conditionId,
            oracle,
            questionId,
            outcomeSlotCount
        );
    }

    /// @dev Called by the oracle for reporting results of conditions. Will set the payout vector for the condition with the ID ``keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount))``, where oracle is the message sender, questionId is one of the parameters of this function, and outcomeSlotCount is the length of the payouts parameter, which contains the payoutNumerators for each outcome slot of the condition.
    /// @param questionId The question ID the oracle is answering for
    /// @param payouts The oracle's answer
    // A B [0, 1] [3, 7]
    function reportPayouts(
        bytes32 questionId,
        uint[] calldata payouts
    ) external {
        uint outcomeSlotCount = payouts.length;

        // IMPORTANT, the oracle is enforced to be the sender because it's part of the hash.
        bytes32 conditionId = CTHelpers.getConditionId(
            msg.sender,
            questionId,
            outcomeSlotCount
        );
        require(
            payoutNumerators[conditionId].length == outcomeSlotCount,
            "condition not prepared or found"
        );
        require(
            payoutDenominator[conditionId] == 0,
            "payout denominator already set"
        );

        uint den = 0;
        for (uint i = 0; i < outcomeSlotCount; i++) {
            uint num = payouts[i];
            den = den.add(num);

            require(
                payoutNumerators[conditionId][i] == 0,
                "payout numerator already set"
            );
            payoutNumerators[conditionId][i] = num;
        }
        require(den > 0, "payout is all zeroes");
        payoutDenominator[conditionId] = den;
        emit ConditionResolution(
            conditionId,
            msg.sender,
            questionId,
            outcomeSlotCount,
            payoutNumerators[conditionId]
        );
    }

    /// @dev This function splits a position. If splitting from the collateral, this contract will attempt to transfer `amount` collateral from the message sender to itself. Otherwise, this contract will burn `amount` stake held by the message sender in the position being split worth of EIP 1155 tokens. Regardless, if successful, `amount` stake will be minted in the split target positions. If any of the transfers, mints, or burns fail, the transaction will revert. The transaction will also revert if the given partition is trivial, invalid, or refers to more slots than the condition is prepared with.
    /// @param collateralToken The address of the positions' backing collateral token.
    /// @param conditionId The ID of the condition to split on.
    /// @param amount The amount of collateral or stake to split.
    function splitPosition(
        IERC20 collateralToken,
        bytes32 conditionId,
        uint amount
    ) external {
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        require(outcomeSlotCount > 0, "condition not prepared yet");

        uint[] memory positionIds = new uint[](outcomeSlotCount);
        uint[] memory amounts = new uint[](outcomeSlotCount);
        for (uint i = 0; i < outcomeSlotCount; i++) {
            positionIds[i] = CTHelpers.getPositionId(
                collateralToken,
                CTHelpers.getCollectionId(bytes32(0), conditionId, i)
            );
            amounts[i] = amount;
        }

        require(
            collateralToken.transferFrom(msg.sender, address(this), amount),
            "could not receive collateral tokens"
        );
        _batchMint(
            msg.sender,
            // position ID is the ERC 1155 token ID
            positionIds,
            amounts,
            ""
        );
        emit PositionSplit(msg.sender, collateralToken, conditionId, amount);
    }

    function mergePositions(
        IERC20 collateralToken,
        bytes32 conditionId,
        uint amount
    ) external {
        uint outcomeSlotCount = payoutNumerators[conditionId].length;

        uint[] memory positionIds = new uint[](outcomeSlotCount);
        uint[] memory amounts = new uint[](outcomeSlotCount);

        for (uint i = 0; i < outcomeSlotCount; i++) {
            positionIds[i] = CTHelpers.getPositionId(
                collateralToken,
                CTHelpers.getCollectionId(bytes32(0), conditionId, i)
            );
            amounts[i] = amount;
        }

        _batchBurn(msg.sender, positionIds, amounts);

        require(
            collateralToken.transfer(msg.sender, amount),
            "could not send collateral tokens"
        );

        emit PositionsMerge(msg.sender, collateralToken, conditionId, amount);
    }

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 conditionId
    ) external {
        uint outcomeSlotCount = payoutNumerators[conditionId].length;
        uint den = payoutDenominator[conditionId];
        require(den > 0, "result for condition not received yet");

        uint totalPayout = 0;
        for (uint i = 0; i < outcomeSlotCount; i++) {
            uint positionId = CTHelpers.getPositionId(
                collateralToken,
                CTHelpers.getCollectionId(bytes32(0), conditionId, i)
            );
            uint payoutNumerator = payoutNumerators[conditionId][i];
            uint payoutStake = balanceOf(msg.sender, positionId);
            if (payoutStake > 0) {
                totalPayout = totalPayout.add(
                    payoutStake.mul(payoutNumerator).div(den)
                );
                _burn(msg.sender, positionId, payoutStake);
            }
        }

        if (totalPayout > 0) {
            require(
                collateralToken.transfer(msg.sender, totalPayout),
                "could not transfer payout to message sender"
            );
        }
        emit PayoutRedemption(
            msg.sender,
            collateralToken,
            conditionId,
            totalPayout
        );
    }

    /// @dev Gets the outcome slot count of a condition.
    /// @param conditionId ID of the condition.
    /// @return Number of outcome slots associated with a condition, or zero if condition has not been prepared yet.
    function getOutcomeSlotCount(
        bytes32 conditionId
    ) external view returns (uint) {
        return payoutNumerators[conditionId].length;
    }

    /// @dev Constructs a condition ID from an oracle, a question ID, and the outcome slot count for the question.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint outcomeSlotCount
    ) external pure returns (bytes32) {
        return CTHelpers.getConditionId(oracle, questionId, outcomeSlotCount);
    }

    /// @dev Constructs an outcome collection ID from a parent collection and an outcome collection.
    /// @param parentCollectionId Collection ID of the parent outcome collection, or bytes32(0) if there's no parent.
    /// @param conditionId Condition ID of the outcome collection to combine with the parent outcome collection.
    /// @param indexSet Index set of the outcome collection to combine with the parent outcome collection.
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint indexSet
    ) external view returns (bytes32) {
        return
            CTHelpers.getCollectionId(
                parentCollectionId,
                conditionId,
                indexSet
            );
    }

    /// @dev Constructs a position ID from a collateral token and an outcome collection. These IDs are used as the ERC-1155 ID for this contract.
    /// @param collateralToken Collateral token which backs the position.
    /// @param collectionId ID of the outcome collection associated with this position.
    function getPositionId(
        IERC20 collateralToken,
        bytes32 collectionId
    ) external pure returns (uint) {
        return CTHelpers.getPositionId(collateralToken, collectionId);
    }
}
