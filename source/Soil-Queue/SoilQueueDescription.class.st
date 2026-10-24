"
What makes a queue a resident: I create it when the database opens and let the resident
machinery start it, and the start configures it. The queue itself works on its workspace, a
SoilQueueWorkspace, and runs the same with or without me around it.

I hold that workspace and the configuration -- how many workers, how often an entry may
come back, and the backoff. None of that shapes a key; what does, the index and the format,
belongs to the workspace, because whoever opens it without me still has to find the
entries. I am read to configure the queue at every start, and only then: my values go to
its lanes, which hold them until the next start. The queue reaches its
workspace by id.

I am the one place these values are set and checked. A live lane has no setters for
them; it reads what holds for it off me once, when it is built (#valueAt:forLane:). A
queue without a resident is configured the same way, from one of me that is never stored
(SoilQueue class>>#onWorkspace:configuredFrom:in:).

Every value is set for all lanes, and may be set for one lane in particular, by the same
selector with forLane:. A lane takes what is set for it and the rest from what is set
for all -- the worker limit as much as the limit for entries given back and the backoff.
Set to nil for a lane counts as set: a lane can go without a limit that holds for all
the others. Kept by lane name, since the lanes themselves are the workspace's.

The workspace is a cluster root of its own. I make it one in #initializeFrom:, which is
where a description creates the objects its resident works on, and it makes the index
and the dead letters roots in turn. That also spares the queue a trap: Soil sends
#soilClusterRootIn: only out of #makeRoot:, never to an object it promotes on its own
because the class says #isSoilClusterRoot -- so an index that only ever arrived by
reference would be stored with no transaction at all.

My name is a constant, #queue, as for every pair of resident and description: one queue
to a database. A second queue in one database would be a pair of subclasses with a name
of its own.
"
Class {
	#name : #SoilQueueDescription,
	#superclass : #SoilResidentDescription,
	#instVars : [
		'workerLimit',
		'orphanedRetryLimit',
		'backoffBase',
		'backoffCap',
		'laneValues'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueDescription class >> timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes [
	"the ordinary queue: an index of its own, ordered by due time. Any other workspace is
	handed to a new one of me (#workspace:)"

	^ self new
		workspace: (SoilQueueWorkspace timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes);
		yourself
]

{ #category : #retrying }
SoilQueueDescription >> backoffBase [
	"the pause before an entry that was given back comes again the first time. Every further
	time in a row doubles it, up to #backoffCap. One second by default, so that a short
	disturbance around the work -- a commit that did not go through, a segment that is not
	there yet -- is over quickly"

	^ backoffBase ifNil: [ 1 second ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffBase: aDuration [

	(self checkBackoff: aDuration) ifTrue: [ backoffBase := aDuration ]
]

{ #category : #lanes }
SoilQueueDescription >> backoffBase: aDuration forLane: aSymbol [

	(self checkBackoff: aDuration) ifTrue: [
		(self valuesForLane: aSymbol) at: #backoffBase put: aDuration ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffCap [
	"the longest pause before an entry that was given back comes again, however often in a
	row that happened. An hour by default"

	^ backoffCap ifNil: [ 1 hour ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffCap: aDuration [

	(self checkBackoff: aDuration) ifTrue: [ backoffCap := aDuration ]
]

{ #category : #lanes }
SoilQueueDescription >> backoffCap: aDuration forLane: aSymbol [

	(self checkBackoff: aDuration) ifTrue: [
		(self valuesForLane: aSymbol) at: #backoffCap put: aDuration ]
]

{ #category : #private }
SoilQueueDescription >> checkBackoff: aDuration [
	"no wait at all is a wait of nothing, and allowed; no duration is not -- set for a lane,
	nil counts as set, and the lane would have nothing to compute its wait from. For the
	base and the cap alike -- see #checkOrphanedRetryLimit:"

	(aDuration isNil or: [ aDuration negative ]) ifTrue: [
		self error: 'a backoff is a duration of zero or more'.
		^ false ].
	^ true
]

{ #category : #private }
SoilQueueDescription >> checkOrphanedRetryLimit: anInteger [
	"when it is set, for all lanes or for one, and not at the next start, where it would
	keep the resident from coming up. Answers whether it may be stored: a refusal that is
	proceeded in the debugger returns here, and must not store the value all the same"

	(anInteger notNil and: [ anInteger < 0 ]) ifTrue: [
		self error: 'a negative number of retries cannot be used up'.
		^ false ].
	^ true
]

{ #category : #private }
SoilQueueDescription >> checkWorkerLimit: anInteger [
	"when it is set, for all lanes or for one -- see #checkOrphanedRetryLimit:"

	anInteger < 1 ifTrue: [
		self error: 'a lane with no worker would never run'.
		^ false ].
	^ true
]

{ #category : #initialization }
SoilQueueDescription >> initializeFrom: aTransaction [
	"my workspace is a cluster root of its own -- that is what gives it the id the queue
	reaches it by, without reading me. Made a root first, then asked to make its own
	roots, the index and the dead letters"

	aTransaction makeRoot: workspace.
	workspace initializeIn: aTransaction
]

{ #category : #'instance creation' }
SoilQueueDescription >> instanceClass [

	^ SoilQueue
]

{ #category : #accessing }
SoilQueueDescription >> name [
	"the registry key, the same for every queue -- see my class comment"

	^ #queue
]

{ #category : #accessing }
SoilQueueDescription >> orphanedRetryLimit [
	"how often in a row an entry may lose its worker and be given back before it is parked
	as a dead letter -- a step of it that goes through ends the row. nil means no limit,
	and nil is the default: an entry that takes its worker with it every time -- the poison
	entry -- is the case the limit is for, and how many lost workers in a row are too many
	depends on what the work does and how often the embedder deploys. That is the
	embedder's knowledge; a number here would be a guess"

	^ orphanedRetryLimit
]

{ #category : #accessing }
SoilQueueDescription >> orphanedRetryLimit: anInteger [

	(self checkOrphanedRetryLimit: anInteger) ifTrue: [ orphanedRetryLimit := anInteger ]
]

{ #category : #lanes }
SoilQueueDescription >> orphanedRetryLimit: anInteger forLane: aSymbol [
	"nil for no limit, as for all lanes -- set for this lane, it overrides a limit set for
	all of them"

	(self checkOrphanedRetryLimit: anInteger) ifTrue: [
		(self valuesForLane: aSymbol) at: #orphanedRetryLimit put: anInteger ]
]

{ #category : #printing }
SoilQueueDescription >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << self name
]

{ #category : #lanes }
SoilQueueDescription >> valueAt: aValueName forLane: aSymbol [
	"what holds for that lane: what is set for it in particular, else what is set for all
	lanes, else the default -- the getter of that name answers the last two. Set to nil for
	the lane counts as set, which is how a lane goes without a limit that holds for all the
	others. Read once, when the lane is built"

	laneValues ifNotNil: [
		(laneValues at: aSymbol ifAbsent: [ nil ]) ifNotNil: [ :values |
			(values includesKey: aValueName) ifTrue: [ ^ values at: aValueName ] ] ].
	^ self perform: aValueName
]

{ #category : #lanes }
SoilQueueDescription >> valuesForLane: aSymbol [
	"what is set for that lane in particular, to be added to"

	laneValues ifNil: [ laneValues := Dictionary new ].
	^ laneValues at: aSymbol ifAbsentPut: [ Dictionary new ]
]

{ #category : #accessing }
SoilQueueDescription >> workerLimit [
	"how many workers of a lane may run at once, for every lane that has no limit of its own
	(#workerLimit:forLane:). One unless the embedder says otherwise, and that is the
	cautious direction: in Pharo processes are green threads, so more of them buy overlap
	during waiting and latency isolation between a long entry and a short one, never
	throughput. Against a backlog more workers are no answer."

	^ workerLimit ifNil: [ 1 ]
]

{ #category : #accessing }
SoilQueueDescription >> workerLimit: anInteger [

	(self checkWorkerLimit: anInteger) ifTrue: [ workerLimit := anInteger ]
]

{ #category : #lanes }
SoilQueueDescription >> workerLimit: anInteger forLane: aSymbol [
	"how many workers of that lane may run at once. Its places are its own: no other lane
	takes them, and it takes none of theirs"

	(self checkWorkerLimit: anInteger) ifTrue: [
		(self valuesForLane: aSymbol) at: #workerLimit put: anInteger ]
]

