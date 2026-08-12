import Foundation

struct AuthUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

struct Profile: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    let email: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case avatarUrl = "avatar_url"
    }
}

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
    case blocked
}

struct Friendship: Codable, Identifiable, Equatable {
    let id: String
    let requesterId: String
    let addresseeId: String
    let status: FriendshipStatus
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case createdAt = "created_at"
    }
}

struct FriendRow: Identifiable, Equatable {
    let friendship: Friendship
    let profile: Profile?

    var id: String { friendship.id }
}

struct CalendarEvent: Codable, Identifiable, Equatable {
    let id: String?
    let userId: String
    let title: String
    let startAt: String
    let endAt: String
    let color: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, title, color, source
        case userId = "user_id"
        case startAt = "start_at"
        case endAt = "end_at"
    }
}

struct CalendarSource: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let label: String
    let kind: String
    let icsUrl: String?
    let deviceCalendarId: String?
    let lastSyncedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, label, kind
        case userId = "user_id"
        case icsUrl = "ics_url"
        case deviceCalendarId = "device_calendar_id"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }
}

struct PoteGroup: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let ownerId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

struct GroupMember: Codable, Equatable {
    let groupId: String
    let userId: String
    let role: String
    let joinedAt: String?

    enum CodingKeys: String, CodingKey {
        case role
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct GroupMemberRow: Identifiable, Equatable {
    let member: GroupMember
    let profile: Profile?

    var id: String { member.userId }
}

struct BusyEvent: Codable, Equatable {
    let userId: String
    let startAt: String
    let endAt: String
    let title: String?

    enum CodingKeys: String, CodingKey {
        case title
        case userId = "user_id"
        case startAt = "start_at"
        case endAt = "end_at"
    }
}

enum OutingResponse: String, Codable {
    case pending
    case accepted
    case declined
}

struct Outing: Codable, Identifiable, Equatable {
    let id: String
    let creatorId: String
    let groupId: String?
    let title: String
    let startsAt: String
    let endsAt: String
    let location: String?
    let note: String?
    let cancelledAt: String?
    let confirmedAt: String?
    let messageRetentionDays: Int

    enum CodingKeys: String, CodingKey {
        case id, title, location, note
        case creatorId = "creator_id"
        case groupId = "group_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case cancelledAt = "cancelled_at"
        case confirmedAt = "confirmed_at"
        case messageRetentionDays = "message_retention_days"
    }
}

struct OutingParticipant: Codable, Equatable {
    let outingId: String
    let userId: String
    let response: OutingResponse
    let respondedAt: String?
    let remindedAt: String?

    enum CodingKeys: String, CodingKey {
        case response
        case outingId = "outing_id"
        case userId = "user_id"
        case respondedAt = "responded_at"
        case remindedAt = "reminded_at"
    }
}

struct ReceivedOutingRow: Identifiable, Equatable {
    let outing: Outing
    let participant: OutingParticipant

    var id: String { outing.id }
    var response: OutingResponse { participant.response }
}

struct OutingParticipantRow: Identifiable, Equatable {
    let participant: OutingParticipant
    let profile: Profile?

    var id: String { participant.userId }
}

struct SentOutingRow: Identifiable, Equatable {
    let outing: Outing
    let participants: [OutingParticipantRow]

    var id: String { outing.id }
}

struct OutingMessageSenderProfile: Codable, Equatable {
    let username: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case username
        case avatarUrl = "avatar_url"
    }
}

struct OutingMessage: Codable, Identifiable, Equatable {
    let id: String
    let outingId: String
    let senderId: String
    let body: String
    let mentionedUserIds: [String]
    let createdAt: String
    let profile: OutingMessageSenderProfile?

    enum CodingKeys: String, CodingKey {
        case id, body, profile
        case outingId = "outing_id"
        case senderId = "sender_id"
        case mentionedUserIds = "mentioned_user_ids"
        case createdAt = "created_at"
    }
}
