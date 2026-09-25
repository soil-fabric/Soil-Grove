"
What makes a queue a resident: I create it when the database opens, configure it, and
let the resident machinery start it. The queue itself works on its workspace, a
SoilQueueWorkspace, and runs the same with or without me around it.

I hold that workspace and the configuration -- how many workers, the rate, the retry
budgets and the backoff. None of that shapes a key; what does, the index and the format,
belongs to the workspace, because whoever opens it without me still has to find the
entries. I am read to create and configure the queue at every start, and only then: my
values go to its lanes, which hold them until the next start. The queue reaches its
workspace by id.

Every value is set for all lanes, and may be set for one lane in particular, by the
same selector with forLane:. A lane takes what is set for it and the rest from what is set
for all. Likewise every lane draws on the worker pool named for it, #default if none is:
#default has the worker limit as its size, any other pool the size set by
#workerPool:size:. Kept by lane name, since the lanes themselves are the workspace's.

The workspace is a cluster root of its own. I make it one in #initializeFrom:, which is
where a description creates the objects its resident works on, and it makes the index
and the dead letters roots in turn. That also spares the queue a trap: Soil sends
#soilClusterRootIn: only out of #makeRoot:, never to an object it promotes on its own
because the class says #isSoilClusterRoot -- so an index that only ever arrived by
reference would be stored with no transaction at all.

My name is an instance variable rather than a constant of my class, which is where the
resident system usually puts it. A queue is created at runtime and there can be many,
and the registry keys by name.
"
Class {
	#name : #SoilQueueDescription,
	#superclass : #SoilResidentDescription,
	#instVars : [
		'name',
		'workerLimit',
		'orphanedRetryLimit',
		'failureRetryLimit',
		'backoffBase',
		'backoffCap',
		'rateLimit',
		'ratePeriod',
		'laneValues',
		'poolSizes'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueDescription class >> named: aSymbol timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes [
	"the ordinary queue: an index of its own, ordered by due time"

	^ self
		named: aSymbol
		workspace: (SoilQueueWorkspace timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes)
]

{ #category : #'instance creation' }
SoilQueueDescription class >> named: aSymbol workspace: aQueueWorkspace [

	^ self new
		setName: aSymbol
		workspace: aQueueWorkspace
]

{ #category : #retrying }
SoilQueueDescription >> backoffBase [
	"the pause before the first retry. Every further failure doubles it, up to
	#backoffCap. One second by default, so that a short disturbance -- a dropped
	connection -- is over quickly"

	^ backoffBase ifNil: [ 1 second ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffBase: aDuration [

	backoffBase := aDuration
]

{ #category : #lanes }
SoilQueueDescription >> backoffBase: aDuration forLane: aSymbol [

	(self valuesForLane: aSymbol) at: #backoffBase put: aDuration
]

{ #category : #retrying }
SoilQueueDescription >> backoffCap [
	"the longest pause between two retries, however often the work has failed. An hour by
	default"

	^ backoffCap ifNil: [ 1 hour ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffCap: aDuration [

	backoffCap := aDuration
]

{ #category : #lanes }
SoilQueueDescription >> backoffCap: aDuration forLane: aSymbol [

	(self valuesForLane: aSymbol) at: #backoffCap put: aDuration
]

{ #category : #lanes }
SoilQueueDescription >> configureLane: aLane [
	"what is set for this lane in particular, over the values it took from those for all
	lanes. Only what is set: a lane with nothing of its own keeps them all"

	| values |
	values := laneValues ifNil: [ ^ self ].
	values := values at: aLane name ifAbsent: [ ^ self ].
	values at: #rate ifPresent: [ :rate | aLane rateLimit: rate key per: rate value ].
	values at: #failureRetryLimit ifPresent: [ :limit | aLane failureRetryLimit: limit ].
	values at: #orphanedRetryLimit ifPresent: [ :limit | aLane orphanedRetryLimit: limit ].
	values at: #backoffBase ifPresent: [ :duration | aLane backoffBase: duration ].
	values at: #backoffCap ifPresent: [ :duration | aLane backoffCap: duration ]
]

{ #category : #retrying }
SoilQueueDescription >> failureRetryLimit [
	"how often a work unit that failed retriably is tried again before the entry gives up.
	Three by default. A retry is only ever asked for by an entry that calls an error
	retriable, and what it costs -- a far side hit again, a quota used up -- is why the
	budget is narrow"

	^ failureRetryLimit ifNil: [ 3 ]
]

{ #category : #retrying }
SoilQueueDescription >> failureRetryLimit: anInteger [

	anInteger < 0 ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	failureRetryLimit := anInteger
]

{ #category : #lanes }
SoilQueueDescription >> failureRetryLimit: anInteger forLane: aSymbol [

	anInteger < 0 ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	(self valuesForLane: aSymbol) at: #failureRetryLimit put: anInteger
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

	^ name
]

{ #category : #'instance creation' }
SoilQueueDescription >> newInstanceIn: aTransaction [
	"the name goes along, so the live queue can answer for itself what it is called
	without opening a transaction for a label. So does the configuration: the queue builds
	its lanes from my workspace and my values right here, and again at every start"

	^ (super newInstanceIn: aTransaction)
		name: name;
		configureFrom: self in: aTransaction;
		yourself
]

{ #category : #accessing }
SoilQueueDescription >> orphanedRetryLimit [
	"how often an entry may lose its worker and be given back before it is parked as a dead
	letter. nil means no limit, and nil is the default: an entry that takes its worker
	with it every time -- the poison entry -- is the case the limit is for, and how many
	lost workers are too many depends on what the work does and how often the embedder
	deploys. That is the embedder's knowledge; a number here would be a guess"

	^ orphanedRetryLimit
]

{ #category : #accessing }
SoilQueueDescription >> orphanedRetryLimit: anInteger [

	(anInteger notNil and: [ anInteger < 0 ]) ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	orphanedRetryLimit := anInteger
]

{ #category : #lanes }
SoilQueueDescription >> orphanedRetryLimit: anInteger forLane: aSymbol [
	"nil for no limit, as for all lanes -- set for this lane, it overrides a limit set for
	all of them"

	(anInteger notNil and: [ anInteger < 0 ]) ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	(self valuesForLane: aSymbol) at: #orphanedRetryLimit put: anInteger
]

{ #category : #printing }
SoilQueueDescription >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name
]

{ #category : #rate }
SoilQueueDescription >> rateLimit [
	"how many entries may be handed out in any period of #ratePeriod, or nil for no rate at
	all -- the default, and how a queue ran before it had one. A number here is what a far
	side accepts per so long; it is the embedder's to know.

	The rate of every lane that has none of its own: work that needs a pace of its own gets
	a lane of its own, and its rate by #rateLimit:per:forLane:"

	^ rateLimit
]

{ #category : #rate }
SoilQueueDescription >> rateLimit: anInteger per: aDuration [
	"no more than anInteger entries handed out in any period of aDuration. Any period, not
	the one on the clock: a burst up to the limit may go at once, and then the rate waits
	until the oldest of it is aDuration ago"

	anInteger < 1 ifTrue: [ ^ self error: 'a rate that lets nothing out would stop the queue' ].
	rateLimit := anInteger.
	ratePeriod := aDuration
]

{ #category : #lanes }
SoilQueueDescription >> rateLimit: anInteger per: aDuration forLane: aSymbol [

	anInteger < 1 ifTrue: [ ^ self error: 'a rate that lets nothing out would stop the lane' ].
	(self valuesForLane: aSymbol) at: #rate put: anInteger -> aDuration
]

{ #category : #rate }
SoilQueueDescription >> ratePeriod [
	"the length of the period #rateLimit counts in"

	^ ratePeriod
]

{ #category : #initialization }
SoilQueueDescription >> setName: aSymbol workspace: aQueueWorkspace [

	name := aSymbol.
	workspace := aQueueWorkspace
]

{ #category : #lanes }
SoilQueueDescription >> sizeOfWorkerPool: aSymbol [
	"how many places a pool has: #default has the worker limit, any other what it was set
	to -- one if nothing was, the cautious direction, as for the worker limit"

	aSymbol = #default ifTrue: [ ^ self workerLimit ].
	^ (poolSizes ifNil: [ ^ 1 ]) at: aSymbol ifAbsent: [ 1 ]
]

{ #category : #lanes }
SoilQueueDescription >> valuesForLane: aSymbol [
	"what is set for that lane in particular, to be added to"

	laneValues ifNil: [ laneValues := Dictionary new ].
	^ laneValues at: aSymbol ifAbsentPut: [ Dictionary new ]
]

{ #category : #accessing }
SoilQueueDescription >> workerLimit [
	"how many workers may run at once: the size of the worker pool all lanes share. One
	unless the embedder says otherwise, and that is the cautious direction: in Pharo
	processes are green threads, so more of them buy overlap during waiting and latency
	isolation between a long entry and a short one, never throughput. Against a backlog
	the answer is a different rate, not more workers."

	^ workerLimit ifNil: [ 1 ]
]

{ #category : #accessing }
SoilQueueDescription >> workerLimit: anInteger [

	anInteger < 1 ifTrue: [ ^ self error: 'a queue with no worker would never run' ].
	workerLimit := anInteger
]

{ #category : #lanes }
SoilQueueDescription >> workerPool: aPoolName forLane: aSymbol [
	"the lane draws its workers from that pool. Lanes named for one pool share it; a lane
	named for none draws on #default"

	(self valuesForLane: aSymbol) at: #workerPool put: aPoolName
]

{ #category : #lanes }
SoilQueueDescription >> workerPool: aSymbol size: anInteger [
	"how many workers of the lanes drawing on that pool may run at once. For #default that
	is the worker limit"

	aSymbol = #default ifTrue: [ ^ self workerLimit: anInteger ].
	anInteger < 1 ifTrue: [ ^ self error: 'a pool with no place would never let a worker run' ].
	poolSizes ifNil: [ poolSizes := Dictionary new ].
	poolSizes at: aSymbol put: anInteger
]

{ #category : #lanes }
SoilQueueDescription >> workerPoolForLane: aSymbol [
	"the name of the pool that lane draws on"

	^ ((laneValues ifNil: [ ^ #default ]) at: aSymbol ifAbsent: [ ^ #default ])
		at: #workerPool ifAbsent: [ #default ]
]
