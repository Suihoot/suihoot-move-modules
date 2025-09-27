# Suihoot - On-Chain Kahoot Game System

A decentralized quiz game system built on Sui blockchain with encrypted questions using Seal and Walrus storage.

## Overview

Suihoot is an on-chain implementation of a Kahoot-style quiz game where:

1. **Room Creation**: Creators encrypt questions using Seal and store them on Walrus
2. **Participant Management**: Players can join open rooms
3. **On-Chain Decryption**: Questions are decrypted on-chain during gameplay
4. **Secure Answering**: Answers are hashed and compared on-chain
5. **Leaderboard**: Real-time scoring and ranking system
6. **Prize Distribution**: Winners can be rewarded automatically

## Architecture

### Core Components

- **GameRoom**: Main game state object shared among participants
- **EncryptedQuestion**: Questions encrypted with Seal and stored on Walrus
- **Participant**: Player information and answers
- **CreatorCap**: Capability token for room creators
- **Leaderboard**: Ranking system based on scores

### Game States

- **0 - Open**: Room is accepting participants
- **1 - Started**: Game is in progress
- **2 - Completed**: Game finished, leaderboard finalized

## Usage

### 1. Creating a Room

```move
// Prepare encrypted questions
let mut questions = vector::empty<EncryptedQuestion>();

// Each question is encrypted with Seal and stored on Walrus
let encrypted_q1 = room::new_encrypted_question(
    string::utf8(b"walrus_hash_abc123"),     // Walrus storage hash
    sealed_question_data,                     // Encrypted question data
    hashed_correct_answer,                    // Hash of correct answer
    100                                       // Points for correct answer
);

vector::push_back(&mut questions, encrypted_q1);

// Create the room
let (room, creator_cap) = room::create_room(
    string::utf8(b"My Quiz Room"),
    string::utf8(b"A fun quiz about blockchain"),
    questions,
    50,                                       // Max participants
    &clock,
    ctx
);

// Share the room for others to join
transfer::share_object(room);
```

### 2. Joining a Room

```move
// Players can join an open room
room::join_room(&mut room, &clock, ctx);
```

### 3. Starting the Game

```move
// Only the creator can start the game
room::start_game(&mut room, &creator_cap, &clock, ctx);
```

### 4. Answering Questions

```move
// Players submit their answers
room::submit_answer(&mut room, string::utf8(b"Option A"), &clock, ctx);
```

### 5. Progressing Through Questions

```move
// Creator moves to next question
room::next_question(&mut room, &creator_cap, &clock, ctx);
```

## Integration with Seal and Walrus

### Question Encryption Process

1. **Client-Side Encryption**:
   ```typescript
   // Pseudocode for frontend integration
   const questionData = {
     question: "What is the capital of France?",
     options: ["London", "Berlin", "Paris", "Madrid"],
     correctAnswer: "Paris"
   };
   
   // Encrypt with Seal
   const sealedData = await seal.encrypt(JSON.stringify(questionData));
   
   // Store on Walrus
   const walrusHash = await walrus.store(sealedData);
   
   // Hash the correct answer
   const answerHash = keccak256("Paris");
   
   // Create encrypted question for Move contract
   const encryptedQuestion = {
     walrus_hash: walrusHash,
     sealed_data: sealedData,
     answer_hash: answerHash,
     points: 100
   };
   ```

2. **On-Chain Decryption**:
   ```move
   // In the reveal_question function
   let (question_text, options) = decrypt_with_seal(&encrypted_q.sealed_data);
   ```

### Answer Verification

```move
// Hash submitted answer and compare with stored hash
let answer_hash = hash::keccak256(string::as_bytes(&answer));
let is_correct = answer_hash == current_question.correct_answer_hash;
```

## Events

The contract emits various events for frontend integration:

- `RoomCreated`: When a new room is created
- `ParticipantJoined`: When a player joins
- `GameStarted`: When the game begins
- `QuestionRevealed`: When a question is decrypted and shown
- `AnswerSubmitted`: When a player submits an answer
- `QuestionCompleted`: When time expires or all players answer
- `GameCompleted`: When the game ends

## API Reference

### View Functions

```move
// Get room information
public fun get_room_info(room: &GameRoom): (String, String, u8, u64, u64, u64)

// Get current question details
public fun get_current_question(room: &GameRoom): (String, vector<String>, u64, u64)

// Get participant score
public fun get_participant_score(room: &GameRoom, participant: address): u64

// Get leaderboard
public fun get_leaderboard(room: &GameRoom): vector<LeaderboardEntry>

// Check if participant answered current question
public fun has_answered_current_question(room: &GameRoom, participant: address): bool
```

### Error Codes

- `ENotCreator`: Only the room creator can perform this action
- `ERoomNotOpen`: Room is not accepting participants
- `ERoomFull`: Room has reached maximum capacity
- `EAlreadyJoined`: Participant already joined this room
- `ENotParticipant`: Address is not a participant in this room
- `ERoomNotStarted`: Game has not been started yet
- `EQuestionNotActive`: No active question to answer
- `EAlreadyAnswered`: Participant already answered current question
- `ETimeExpired`: Answer submission time has expired
- `EInvalidQuestionIndex`: Question index is out of bounds

## Testing

Run the tests to verify functionality:

```bash
sui move test
```

The test suite includes:
- Room creation and setup
- Participant joining
- Game flow from start to finish
- Answer submission and verification

## Security Considerations

1. **Encryption**: Questions are encrypted client-side with Seal before being stored
2. **Immutable Storage**: Walrus provides immutable storage for encrypted questions
3. **Hash Verification**: Answers are verified through cryptographic hashes
4. **Time Limits**: Answer submission has built-in time constraints
5. **Access Control**: Only room creators can control game progression

## Frontend Integration

The system is designed to work with a web frontend that:

1. Encrypts questions using Seal before submission
2. Stores encrypted data on Walrus
3. Creates Move transactions for game interactions
4. Listens to blockchain events for real-time updates
5. Handles decryption for question display

## Future Enhancements

- **Prize Pools**: Automatic distribution of prizes to winners
- **Advanced Scoring**: Time-based scoring algorithms
- **Question Categories**: Support for different question types
- **Team Mode**: Multi-player team competitions
- **NFT Rewards**: Award NFTs to top performers
- **Tournament System**: Multi-round tournament support

## License

This project is open source and available under the MIT License.
