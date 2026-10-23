"
The format that keeps the entries of a group in order: the group first, then a sequence
number within it, then the entry's id.

The group comes first so that all entries of one group lie together and the first of
them is the one to go next. The sequence says where in the group an entry stands, and it
is handed out here when the entry comes in -- one more than the last one the group holds
in the transaction that adds it, so that entries added in one transaction keep the order
they were added in.

The id comes last, and it is not there for the order. An index does not notice two
transactions writing the same key: the one that commits second overwrites the first,
without a word. Two transactions adding to one group at the same time both see the same
last entry and draw the same number, and without the id one of the two entries would be
gone. With it both stay, and their order between them is open -- which is right, because
two entries added side by side never had one.

Duplicate keys in the index would do without the sequence, but their order is what the
index happens to do and nothing it promises, and every key operation of the queue would
have to name the entry besides the key.

The due time is not in the key. It stays on the entry, so an entry that has to wait holds
up its group where it is instead of moving behind the others: of a chain, the next step
must not run before the one ahead of it.

So a lane of mine is read by its groups. Of each group only the first entry can go, and a
first one that is not due says nothing about the next group; I answer which entry is due
next and how many are from the group heads, one jump per group.

The group comes from the entry (SoilQueueEntry>>#groupId), read once, when it comes in;
from then on the key holds it. A group id is a non-negative integer in eight bytes, the
sequence takes four, the id eight: twenty bytes behind the marker.
"
Class {
	#name : #SoilQueueGroupedKeyFormat,
	#superclass : #SoilQueueKeyFormat,
	#category : #'Soil-Queue'
}

{ #category : #converting }
SoilQueueGroupedKeyFormat >> appendKeyPartsFor: anEntry in: aLaneDescription of: aQueueWorkspace on: aWriteStream [

	| group last sequence |
	group := self groupBytesOf: anEntry.
	last := aQueueWorkspace
		lastKeyFrom: (self firstKeyOfGroup: group in: aLaneDescription range)
		to: (self lastKeyOfGroup: group in: aLaneDescription range).
	sequence := last
		ifNil: [ 1 ]
		ifNotNil: [ (self sequenceIn: last behind: aLaneDescription range width) + 1 ].
	sequence >= (256 raisedTo: 4) ifTrue: [
		^ self error: 'the group of ' , anEntry printString , ' has used up its sequence numbers' ].
	aWriteStream
		nextPutAll: group;
		nextPutAll: (sequence asByteArrayOfSize: 4);
		nextPutAll: anEntry id
]

{ #category : #reading }
SoilQueueGroupedKeyFormat >> dueIn: aLaneDescription of: aQueueWorkspace at: aDateAndTime skipping: aCollection upTo: aLimit do: aBlock [
	"only the first entry of each group can go, so only those count -- and only of a group
	whose first entry is neither out nor claimed: that group goes without, its next entry
	must not overtake it. A first one that is not due says nothing about the next group, so
	all groups are looked at, one jump each, and the earliest of the first ones that are not
	due is the time"

	| count earliest range |
	count := 0.
	range := aLaneDescription range.
	self
		groupHeadsIn: aLaneDescription
		of: aQueueWorkspace
		from: range firstIndexKey
		to: range lastIndexKey
		do: [ :key :entry |
			((aCollection includes: key) or: [ entry isPending not ]) ifFalse: [
				entry readyAt <= aDateAndTime
					ifTrue: [
						count := count + 1.
						count >= aLimit ifTrue: [ ^ aBlock value: count value: nil ] ]
					ifFalse: [
						earliest := earliest
							ifNil: [ entry readyAt ]
							ifNotNil: [ :time | time min: entry readyAt ] ] ] ].
	^ aBlock value: count value: earliest
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> firstKeyOfGroup: aGroup in: aRange [
	"the lowest key a group can have in a section: the group, and nothing behind it"

	^ aRange keyWith: aGroup
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> firstKeyOfGroupOf: aKey in: aRange [

	^ self firstKeyOfGroup: (self groupIn: aKey of: aRange) in: aRange
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> groupBytesOf: anEntry [
	"the group id of anEntry in eight bytes. A negative number is refused rather than
	written, because #asByteArrayOfSize: drops the sign without a word, and -5 would share a
	group with 5. One too large for eight bytes #asByteArrayOfSize: refuses itself"

	| group |
	group := anEntry groupId.
	group ifNil: [ ^ self error: anEntry printString , ' has no group id for a grouped lane' ].
	group isInteger ifFalse: [
		^ self error: 'a group id is a non-negative integer, not ' , group printString ].
	group < 0 ifTrue: [ ^ self error: 'a group id cannot be negative: ' , group printString ].
	^ group asByteArrayOfSize: 8
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> groupIn: aKey of: aRange [
	"the group a key of a section belongs to: the eight bytes behind the section's marker"

	| start |
	start := aRange width + 1.
	^ aKey copyFrom: start to: start + 7
]

{ #category : #reading }
SoilQueueGroupedKeyFormat >> groupHeadsIn: aLaneDescription of: aQueueWorkspace from: aFirstIndexKey to: aLastIndexKey do: aBlock [
	"the first entry of every group that begins between two keys, with its key. One jump per
	group rather than one step per entry: from the head of a group straight past its last
	possible key. The first entry the transaction sees is the head -- one that is done and
	gone is not in the way"

	aQueueWorkspace
		scanFrom: aFirstIndexKey
		to: aLastIndexKey
		do: [ :key :entryBlock |
			aBlock value: key value: entryBlock value.
			(self lastIndexKeyOfGroupOf: key in: aLaneDescription of: aQueueWorkspace) + 1 ]
]

{ #category : #reading }
SoilQueueGroupedKeyFormat >> headOfGroupOf: anIndexKey in: aLaneDescription of: aQueueWorkspace [
	"the first entry of the group a key belongs to, as key -> entry, or nil when the group
	holds nothing any more"

	| keySize first |
	keySize := aQueueWorkspace keySize.
	first := (self
		firstKeyOfGroupOf: (anIndexKey asByteArrayOfSize: keySize)
		in: aLaneDescription range) asIndexKeyOfSize: keySize.
	aQueueWorkspace
		scanFrom: first
		to: (self lastIndexKeyOfGroupOf: anIndexKey in: aLaneDescription of: aQueueWorkspace)
		do: [ :key :entryBlock | ^ key -> entryBlock value ].
	^ nil
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> keyFor: anEntry movedFrom: anIndexKey in: aLaneDescription of: aQueueWorkspace [
	"the key it has. The due time is not in my keys, so an entry that has to wait stays where
	it is and holds up its group, and its due time is read from it"

	^ anIndexKey
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> lastIndexKeyOfGroupOf: anIndexKey in: aLaneDescription of: aQueueWorkspace [
	"the highest key the group of anIndexKey can have, in the form the index compares in"

	| keySize |
	keySize := aQueueWorkspace keySize.
	^ (self
		lastKeyOfGroupOf: (anIndexKey asByteArrayOfSize: keySize)
		in: aLaneDescription range) asIndexKeyOfSize: keySize
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> lastKeyOfGroup: aGroup in: aRange [
	"the highest key a group can have in a section: sequence and id set to all ones, and
	behind them the padding every key has"

	^ aRange keyWith: aGroup , (ByteArray new: 12 withAll: 255)
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> lastKeyOfGroupOf: aKey in: aRange [

	^ self lastKeyOfGroup: (self groupIn: aKey of: aRange) in: aRange
]

{ #category : #reading }
SoilQueueGroupedKeyFormat >> nextDueIn: aLaneDescription of: aQueueWorkspace at: aDateAndTime skipping: aCollection preferring: aPreferredKey after: aLastKey ifNone: aBlock [
	"the first entry of a group, and only of a group whose first entry is not out: the group
	of aPreferredKey if it has one due -- a worker carrying on with its own chain --,
	otherwise the next group behind that of aLastKey, round the end of the lane and back, so
	that low group ids do not always win. Either key may be nil.

	A group whose first entry is out, or claimed with nobody holding it, goes without: its
	next entry must not overtake it. A first entry that is not due does not end the scan
	the way it does on a lane ordered by due time -- a later group may have one that is --
	it only offers its time"

	| range earliest goes start |
	range := aLaneDescription range.
	earliest := nil.
	goes := [ :key :entry |
		((aCollection includes: key) or: [ entry isPending not ])
			ifTrue: [ false ]
			ifFalse: [
				entry readyAt <= aDateAndTime
					ifTrue: [ true ]
					ifFalse: [
						earliest := earliest
							ifNil: [ entry readyAt ]
							ifNotNil: [ :time | time min: entry readyAt ].
						false ] ] ].
	(aPreferredKey notNil and: [ range includesKey: aPreferredKey ]) ifTrue: [
		(self headOfGroupOf: aPreferredKey in: aLaneDescription of: aQueueWorkspace)
			ifNotNil: [ :head |
				(goes value: head key value: head value) ifTrue: [ ^ head key ] ] ].
	start := (aLastKey notNil and: [ range includesKey: aLastKey ])
		ifTrue: [
			(self lastIndexKeyOfGroupOf: aLastKey in: aLaneDescription of: aQueueWorkspace) + 1 ]
		ifFalse: [ range firstIndexKey ].
	self
		groupHeadsIn: aLaneDescription
		of: aQueueWorkspace
		from: start
		to: range lastIndexKey
		do: [ :key :entry | (goes value: key value: entry) ifTrue: [ ^ key ] ].
	self
		groupHeadsIn: aLaneDescription
		of: aQueueWorkspace
		from: range firstIndexKey
		to: start - 1
		do: [ :key :entry | (goes value: key value: entry) ifTrue: [ ^ key ] ].
	^ aBlock cull: earliest
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> partsSize [
	"eight bytes of group id, four of sequence, eight of id"

	^ 20
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> sequenceIn: aKey behind: aMarkerWidth [
	"where the entry under aKey stands in its group -- the four bytes behind the marker and
	the eight of the group id"

	| start |
	start := aMarkerWidth + 9.
	^ (aKey copyFrom: start to: start + 3) asInteger
]

