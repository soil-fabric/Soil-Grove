"
A recording queue whose dispatcher starts its workers without forking them. They are
registered the way a started worker is, and they stay registered until someone runs them.
"
Class {
	#name : #SoilQueueTestUnforkedQueue,
	#superclass : #SoilQueueTestRecordingQueue,
	#category : #'Soil-Queue-Tests'
}

{ #category : #running }
SoilQueueTestUnforkedQueue >> startWorker [

	self workerStarting: (SoilQueueWorker on: self)
]
