"
Where a queue's entries live: which index, and which section of it.

Whoever asks for a queue does not say where it goes. That is my decision, and I have two
answers. A queue can get an index to itself, or it can be a section of one that other
queues share, told apart by a marker in front of every key. The shared index is the
ordinary case, not the constitution -- and either way the queue above me cannot tell the
difference.

I am stored with my queue and I am not a cluster root: I am read whenever it is read and
nowhere else. There is no registry of queues and no central book of which marker is
taken. Only the application knows how many queues it needs; it fixes the marker width
and the key size when it creates the index, and it hands out the markers. Two queues
that end up on the same marker is a mistake made at that moment, which a test catches --
not something to be administered afterwards.

The key size is mine for the same reason the width is: an index cannot change it later,
so it has to be the widest key that will ever be needed, and only the application knows
that number.
"
Class {
	#name : #SoilQueueStrategy,
	#superclass : #Object,
	#instVars : [
		'index',
		'range'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueStrategy class >> on: aSoilIndexedDictionary range: aSoilPrefixRange [
	"the sharing case: hand me an index another queue already lies on, and the section of
	it that is mine"

	^ self new
		setIndex: aSoilIndexedDictionary
		range: aSoilPrefixRange
]

{ #category : #'instance creation' }
SoilQueueStrategy class >> ownIndexWithBackend: anIndexClass keySize: keySizeInBytes [
	"the other case: an index of this queue's own, with no marker and no byte paid for one.

	The skip list level is set because Soil leaves it nil, and a nil one fails on the first
	write with a message that says nothing about what is missing. 16 is what the one
	long-lived collection in the wild uses; a queue that wants another builds its index
	itself and comes in through #on:range:. A B-tree ignores it."

	^ self
		on: ((SoilIndexedDictionary newWithBackend: anIndexClass)
			keySize: keySizeInBytes;
			maxLevel: 16;
			yourself)
		range: (SoilPrefixRange prefix: 0 width: 0 keySize: keySizeInBytes)
]

{ #category : #accessing }
SoilQueueStrategy >> backend [
	"the kind of index my entries lie on, in its durable form. Asked of the persistent
	index and not of the one in hand: a materialized index is wrapped copy-on-write per
	transaction, and that wrapper cannot be used to build a new index with."

	^ index persistentIndex class
]

{ #category : #accessing }
SoilQueueStrategy >> index [

	^ index
]

{ #category : #accessing }
SoilQueueStrategy >> keyWith: aByteArray [
	"place the parts the queue collected inside my section: my marker first, those bytes
	after it, zero padding last, filling the whole key size"

	^ range keyWith: aByteArray
]

{ #category : #serializing }
SoilQueueStrategy >> makeIndexRootIn: aTransaction [
	"my index is a cluster root of its own, and it has to be told so by whoever holds it --
	Soil sends #soilClusterRootIn: only to the objects that are made roots, never down into
	what they reference.

	Two things follow, and both are wanted. The index is not copied into the queue's
	cluster, and two queues that share one index share one object instead of each getting a
	copy that overwrites the other's.

	An index that is already on disk was put there by the queue that created it. It is a
	root already and is not mine to create -- and a second queue reaches it by reading it
	in its own transaction, not by being handed the same detached object. A detached one
	still holds the transaction it was first written in, and serializing it in a later one
	fails a long way from here."

	index isPresentOnDisk ifTrue: [ ^ index ].
	^ aTransaction makeRoot: index
]

{ #category : #accessing }
SoilQueueStrategy >> newIterator [
	"an iterator wired to the transaction the index was read in. Going to the index
	directly would skip that wiring, and with it the read version and the proxies for
	values that make reading consistent"

	^ index newIterator
]

{ #category : #accessing }
SoilQueueStrategy >> range [

	^ range
]

{ #category : #initialization }
SoilQueueStrategy >> setIndex: aSoilIndexedDictionary range: aSoilPrefixRange [

	index := aSoilIndexedDictionary.
	range := aSoilPrefixRange
]
