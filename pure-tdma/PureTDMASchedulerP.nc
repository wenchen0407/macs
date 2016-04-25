/*
 * "Copyright (c) 2007 Washington University in St. Louis.
 * All rights reserved.
 * @author Bo Li
 * @date $Date: 2014/10/17
 */

 #include <stdio.h>

module PureTDMASchedulerP {
	provides {
		interface Init;
		interface SplitControl;
		interface AsyncSend as Send;
		interface AsyncReceive as Receive;
		interface CcaControl[am_id_t amId];
		interface FrameConfiguration as Frame;
	}	
	uses{			
		interface AsyncStdControl as GenericSlotter;
		interface RadioPowerControl;
		interface Slotter;
		interface SlotterControl;
		interface FrameConfiguration;
		interface AsyncSend as SubSend;
		interface AsyncSend as BeaconSend;
		interface AsyncReceive as SubReceive;
		interface AMPacket;
		interface Resend;
		interface PacketAcknowledgements;
		interface Boot;
		interface Leds;
		//interface HplMsp430GeneralIO as Pin;
		
		//Added by Bo
		interface CC2420Config;
		
		//Added by Bo
		interface TossimPacketModelCCA;
		interface TossimComPrintfWrite;
		
		interface SimMote;

		//Added by Wenchen
		//interface LogWrite;
		//interface LogRead;
	}
}
implementation {
	enum { 
		SIMPLE_TDMA_SYNC = 123,
		MAXCHILDREN =1,
		TOTALNODES=2,
		ROOT=2,
	};

	typedef nx_struct logentry_t{
   
    	TestNetworkMsg ONE saved_data[MAXCHILDREN];
    	nx_uint8_t ONE handled_saved_data[MAXCHILDREN];
    
    	nx_uint8_t len;
    	message_t msg; 
  	}logentry_t;

  	logentry_t m_entry;
  	TestNetworkMsg* ONE log_payload;

  	TestNetworkMsg* ONE rcmr;

  	uint8_t isChild=0 ;
  	uint8_t isParent=0;
  	uint8_t isSibling=0;
  	uint8_t self_pos=0;

  	FILE *fp;

	bool init;
	uint32_t slotSize;
	uint32_t bi, sd, cap;
	uint8_t coordinatorId;

	uint8_t i=0;
	uint8_t j=0;
	uint8_t k=0;
	
	message_t *toSend; //this one will become critical later on, and cause segmentation error
	uint8_t toSendLen;

	//Below added by Bo
	//message_t packet;
	
	//uint8_t get_last_hop_status(uint8_t flow_id_t, uint8_t access_type_t, uint8_t hop_count_t);
	//void set_current_hop_status(uint32_t slot_t, uint8_t sender, uint8_t receiver);
	//void set_send_status(uint32_t slot_at_send_done, uint8_t ack_t);
	//void set_send (uint32_t slot_t);
	//uint8_t get_flow_id(uint32_t slot_t, uint8_t sender, uint8_t receiver);
  	


uint8_t up_schedule[2][MAXCHILDREN+1]={//PS for two plants, calculated by Chengjie's program, modified by Lanshun.
	{1, 1},
	{1, 2},
};

uint8_t down_schedule[3][MAXCHILDREN+1]={
	{1, 5, 0, 0},
	{1, 4, 0, 0},
	{3, 1, 2, 3}
};

uint8_t schedule_len = 2;
uint32_t superframe_length = 55; //Real superframe length + 1, to make sure we slot 54 after "%, the mod" processing
	
	bool sync;
	bool requestStop;
	//uint32_t sync_count = 0;
	event void Boot.booted(){}
	
	command error_t Init.init() {		
		printf("hello\n");
		slotSize = 10 * 32;     //10ms
		
		//slotSize = 328;     //10ms		
		
		//bi = 16; //# of slots from original TDMA code
		//sd = 11; //last active slot from original TDMA code
		
		bi = 40000; //# of slots in the supersuperframe with only one slot 0 doing sync
		sd = 40000; //last active slot
		cap = 0; // what is this used for? is this yet another superframe length?
		
		coordinatorId = 0;
		init = FALSE;
		toSend = NULL;
		toSendLen = 0;
		sync = FALSE;
		requestStop = FALSE;
		call SimMote.setTcpMsg(0, 0, 0, 0, 0, 0, 0, 0, 0, 0); //reset TcpMsg

		// initialize logentry_t

		for(i=0; i<schedule_len; i++){
			for(j=1; j<=up_schedule[i][0]; j++){
				if(TOS_NODE_ID == up_schedule[i][j]){
					log_payload = (TestNetworkMsg*)call Send.getPayload(&m_entry.msg, sizeof(TestNetworkMsg));

					// set children list
					if(i!=0){
						log_payload->totalChildren=up_schedule[i-1][0];
						for(k=1; k<=up_schedule[i-1][0]; k++){
							log_payload->children[k-1]=up_schedule[i-1][k];
							printf("Node %d children %d\n", (TOS_NODE_ID%500), log_payload->children[k-1]);
							log_payload->childrenReceive[k-1]=0;
							log_payload->childrenHandle[k-1]=0;
							m_entry.handled_saved_data[k-1]=0;
						}
					}else{
						log_payload->totalChildren=0;
						printf("node total children: %d\n", log_payload->totalChildren);
					}


					// set parent list
					if(i<schedule_len-1){
						log_payload->totalParents=up_schedule[i+1][0];
						for(k=1; k<=up_schedule[i+1][0]; k++){
							log_payload->parents[k-1]=up_schedule[i+1][k];
							printf("Node %d parent %d\n", (TOS_NODE_ID%500), log_payload->parents[k-1]);
						}
					}else{
						log_payload->totalParents=0;
					}
					
					// set sibling list
					log_payload->totalSiblings=up_schedule[i][0];
					for(k=1; k<=up_schedule[i][0]; k++){
						log_payload->siblings[k-1]=up_schedule[i][k];
						printf("Node %d sibling: %d\n", (TOS_NODE_ID%500), log_payload->siblings[k-1]);
					}

					log_payload->source = TOS_NODE_ID;
					log_payload->curr_num=0;

					if(TOS_NODE_ID == 1 || TOS_NODE_ID == 2 || TOS_NODE_ID == 3){
						log_payload->self_data1=TOS_NODE_ID*10;

					}

					if(j==1){
						log_payload->i_am_primary=1;
					}else{
						log_payload->i_am_primary=0;
					}
					printf("node %d i_am_primary: %d\n", (TOS_NODE_ID%500), log_payload->i_am_primary);

				}

			}
		}

		return SUCCESS;		
	}
	
 	command error_t SplitControl.start() {
 		error_t err;
 		if (init == FALSE) {
 			call FrameConfiguration.setSlotLength(slotSize);
 			call FrameConfiguration.setFrameLength(bi + 1);
 			//call FrameConfiguration.setFrameLength(1000);
 		}
 		err = call RadioPowerControl.start();
 		return err;
 	}
 	
 	command error_t SplitControl.stop() {
 		printf("This is sensor: %u and the SplitControl.stop has been reached\n", TOS_NODE_ID);
 		requestStop = TRUE;
 		call GenericSlotter.stop();
 		call RadioPowerControl.stop();
 		return SUCCESS;
 	}
 	
 	event void RadioPowerControl.startDone(error_t error) {
 	 	int i;
 		if (coordinatorId == TOS_NODE_ID) { 		
 			if (init == FALSE) { 
 				signal SplitControl.startDone(error); //start sensor 0
 				call GenericSlotter.start(); //start slot counter
 				call SlotterControl.synchronize(0); //synchronize the rest sensors in the network
 				init = TRUE; 				
 			}
 		} else {
 			if (init == FALSE) {
 				signal SplitControl.startDone(error); //start all non-zero sensors
 				init = TRUE; //initialization done
 			}
 		} 		
	}
	
 	event void RadioPowerControl.stopDone(error_t error)  {
		if (requestStop)  {
			printf("This is sensor: %u and the RadioPowerControl.stopDone has been reached\n", TOS_NODE_ID);
			requestStop = FALSE;
			signal SplitControl.stopDone(error);
		}
	}
 	
 	/****************************
 	 *   Implements the schedule
 	 */ 	
 	async event void Slotter.slot(uint32_t slot) { 		
 		message_t *tmpToSend;
 		uint8_t tmpToSendLen;
 		uint8_t i;
 		
 		if (TOS_NODE_ID == 169){
 				//printf("SENSOR:%u, ABSOLUTE TIME: %s at SLOT:%u.\n", TOS_NODE_ID, sim_time_string(), slot);
 		}
 		
 		if (slot == 0 ) {
 			if (TOS_NODE_ID == 169){
 				printf("!!!!!!!!SENSOR: %u reached SLOT:%u!!!!!!!!!\n", TOS_NODE_ID, slot);
 			}
 		
 			if (coordinatorId == TOS_NODE_ID) {
 				call BeaconSend.send(NULL, 0);
 				printf("SENSOR: %u has done network synchronization in SLOT: %u at time: %s:\n", TOS_NODE_ID, slot, sim_time_string());
 			};
 			return;	
 		}
 		
  		if ((slot % superframe_length) == 0 ) {
 			if (TOS_NODE_ID == 169){
 				printf("SENSOR:%u, is resetting slot to ZERO with SUPERFRAME_LENGTH:%u at SLOT:%u.\n", TOS_NODE_ID, superframe_length, slot);
 			}
 			/*for (i=0; i<schedule_len; i++){
  				schedule[i][8]=0; //re-enable transmission by set the flag bit to 0, implying this transmission is unfinished and to be conducted.
  			}*/
 		}
 		
 		if (slot >= sd+1) {
 			/* //sleep 			
 			if (slot == sd+1) {
 				call RadioPowerControl.stop();
 				//call Pin.clr();
 			}
 			//wakeup
 			if (slot == bi) {
 				call RadioPowerControl.start();
 				//call Pin.set();
 				//call Leds.led0On();
 			}*/
 			return;
 		}
 		if (slot < cap) { 
 		} else {
 			//set_send (slot % superframe_length); //heart beat control
 			//printf("i am node %d at slot: %d\n", TOS_NODE_ID, slot%superframe_length);

 			if(TOS_NODE_ID!=0 && slot ==1){
 				// broadcast messages
 				call CC2420Config.setChannel(22);
  				call CC2420Config.sync();
  				call AMPacket.setDestination(&(m_entry.msg), AM_BROADCAST_ADDR);
  				//call PacketAcknowledgements.requestAck(&packet);
  								
  				//call TossimPacketModelCCA.set_cca(schedule[i][4]); //schedule[i][4]: 0, TDMA; 1, CSMA contending; 2, CSMA steal;	
	  			call SubSend.send(&(m_entry.msg), sizeof(TestNetworkMsg));

	  			 printf("Node %d broadcast initialization messages successfully\n", (TOS_NODE_ID%500));

 			}else if(TOS_NODE_ID!=0 && slot%(TOTALNODES+1)-1 == TOS_NODE_ID){
 				// broadcast messages
 				call CC2420Config.setChannel(22);
  				call CC2420Config.sync();
  				call AMPacket.setDestination(&(m_entry.msg), AM_BROADCAST_ADDR);
  				//call PacketAcknowledgements.requestAck(&packet);
  								
  				//call TossimPacketModelCCA.set_cca(schedule[i][4]); //schedule[i][4]: 0, TDMA; 1, CSMA contending; 2, CSMA steal;	
	  			call SubSend.send(&(m_entry.msg), sizeof(TestNetworkMsg));

	  			 printf("Node %d broadcast messages successfully\n", (TOS_NODE_ID%500));

 			}else if(TOS_NODE_ID!=0 && slot%(TOTALNODES+1)==0){
 				printf("print out root %d message receiving %d data\n", TOS_NODE_ID, log_payload->curr_num);
 				if(TOS_NODE_ID == ROOT){
 					printf("print out root %d message receiving %d data\n", TOS_NODE_ID, log_payload->curr_num);
					fp=fopen("result.txt", "a");
		              fprintf(fp, "%d\n", log_payload->curr_num);  
		              
		              fclose(fp);
		              if(log_payload->curr_num>0){
		                for(i=0; i<log_payload->curr_num; i++){
		                  printf("root received data: %d from node %d\n", log_payload->merged_data[i], log_payload->merged_index[i]);
		                }
		              }
 				}
 				

 				//reset nodes merged data and curr_num of m_entry
				call Init.init();
				printf("node %d is resetted\n", TOS_NODE_ID);
 			}


 		}
 	}

 	async command error_t Send.send(message_t * msg, uint8_t len) {
 		atomic {
 			if (toSend == NULL) {
 				toSend = msg;
 				toSendLen = len;
 				return SUCCESS;
 			}
 		}		
 		return FAIL;
 	}

	async event void SubSend.sendDone(message_t * msg, error_t error) {
		uint32_t slot_at_send_done;
		uint8_t ack_at_send_done;	
		slot_at_send_done = call SlotterControl.getSlot() % superframe_length;
		ack_at_send_done = call PacketAcknowledgements.wasAcked(msg)?1:0;	
		//link failure statistics
		if(ack_at_send_done==0){
			//printf("%u, %u, %u, %u, %u, %u\n", 1, TOS_NODE_ID, call AMPacket.destination(msg), call SlotterControl.getSlot(), call CC2420Config.getChannel(), 0);
		}
		//set_send_status(slot_at_send_done, ack_at_send_done);		
		//printf("Slot: %u, SENSOR:%u, Sent to: %u with %s @ %s\n", call SlotterControl.getSlot(), TOS_NODE_ID, call AMPacket.destination(msg), call PacketAcknowledgements.wasAcked(msg)? "ACK":"NOACK", sim_time_string());
		if (msg == &(m_entry.msg)) {
			if (call AMPacket.type(msg) != SIMPLE_TDMA_SYNC) { 
				signal Send.sendDone(msg, error);
			} else {
			}
		}		
	}
	
 	//provide the send interface
 	async command error_t Send.cancel(message_t *msg) { 
  		atomic {
 			if (toSend == NULL) return SUCCESS;
 			atomic toSend = NULL;
 		}
 		return call SubSend.cancel(msg);
 	}

	/**
	 * Receive
	 */
	async event void SubReceive.receive(message_t *msg, void *payload, uint8_t len) {
		am_addr_t src = call AMPacket.source(msg);
		rcmr = (TestNetworkMsg*)payload; 
		log_payload = (TestNetworkMsg*)call Send.getPayload(&m_entry.msg, sizeof(TestNetworkMsg));
		
		
		
		printf("RECEIVE: %u->%u, SLOT:%u (time: %s), channel: %u\n", rcmr->source,TOS_NODE_ID, call SlotterControl.getSlot(), sim_time_string(), call CC2420Config.getChannel());

		
           // do fault tolerant bitvector
           isChild = 0;
           isParent=0;
           isSibling=0;
           
           printf("Node %d log_payload info: totalchildren: %d, totalParents: %d, totalsiblings: %d\n", TOS_NODE_ID, log_payload->totalChildren, log_payload->totalSiblings, log_payload->totalSiblings);

           for(i=0; i<log_payload->totalChildren; i++){
           	  printf("children: %d\n", log_payload->children[i]);
              if(rcmr->source == log_payload->children[i]){
                isChild=i+1;
              }
           }
           
           printf("isChild: %d\n", isChild);
           
           for(i=0; i<log_payload->totalParents; i++){
              if(rcmr->source == log_payload->parents[i]){
                isParent =i+1;
              }
           }
           
           
           for(i=0; i<log_payload->totalSiblings; i++){
              if(rcmr->source == log_payload->siblings[i]){
                isSibling=i+1;
              }
              if(log_payload->siblings[i]==(TOS_NODE_ID%500)){
                self_pos=i;
              }
           }
           
           
           if(isChild >= 1){
              printf("node %d found child %d\n", (TOS_NODE_ID%500), rcmr->source);
              if(log_payload->i_am_primary==1){
                  // merge the message of the child
                  
                  log_payload->childrenReceive[isChild-1] = 1;
                  log_payload->childrenHandle[isChild-1] = 1;  
                  
                 
                  if(rcmr->self_data1>0){
                    printf("primary parent %d merge child %d message\n", (TOS_NODE_ID%500), rcmr->source);
                    log_payload->merged_index[log_payload->curr_num] = rcmr->source;
                    log_payload->merged_data[log_payload->curr_num] = rcmr->self_data1;
                    log_payload->curr_num++;
                  }
                  
                  
                  if(rcmr->curr_num >0){
                    printf("primary parent %d merge child %d message\n", (TOS_NODE_ID%500), rcmr->source);
                    for(i=0; i<rcmr->curr_num; i++){
                      log_payload->merged_index[log_payload->curr_num]=rcmr->merged_index[i];
                      log_payload->merged_data[log_payload->curr_num] = rcmr->merged_data[i];
                      log_payload->curr_num++;
                    }
                  }
                  
                  
              }else{
                  // save the message of the child
                 
                  log_payload->childrenReceive[isChild-1] = 1;
                  log_payload->childrenHandle[isChild-1] = 0;  
                  
                  if(rcmr->self_data1>0){
                    printf("backup parent %d save child %d self data\n", (TOS_NODE_ID%500), rcmr->source);
                    m_entry.saved_data[isChild-1].source = rcmr->source;
                    m_entry.saved_data[isChild-1].self_data1=rcmr->self_data1;
                    m_entry.saved_data[isChild-1].self_data2=rcmr->self_data2;
                  }
                  
                  
                  if(rcmr->curr_num >0){
                    printf("neighbor number of data: %d saved data start: %d\n", rcmr->curr_num, m_entry.saved_data[isChild-1].curr_num);
                    for(i=0; i<rcmr->curr_num; i++){
                      printf("backup parent %d save child %d message\n", (TOS_NODE_ID%500), rcmr->source);
                      printf("saved index: %d, saved data: %d\n", rcmr->merged_index[i], rcmr->merged_data[i]);
                      m_entry.saved_data[isChild-1].merged_data[i] = rcmr->merged_data[i];
                      m_entry.saved_data[isChild-1].merged_index[i] = rcmr->merged_index[i];
                      m_entry.saved_data[isChild-1].curr_num+=1;
                    }
                    printf("merged %d data\n", m_entry.saved_data[isChild-1].curr_num);
                  }
                  
              }
              
              log_payload->self_data1=0;
           }else if(isParent >=1){
              // do nothing
           
           }else if(isSibling >=1){
              // self position 
              // all the children are common children
              for(i=0; i<log_payload->totalChildren; i++){
                  if(log_payload->childrenReceive[i] == 1 && m_entry.handled_saved_data[i]==0){
                      if(isSibling-1 < self_pos ){
                          if(rcmr->childrenHandle[i]==1 || (rcmr->childrenReceive[i]==1 && rcmr->childrenHandle[i]==0)){
                             log_payload->childrenHandle[i] = 1;
                             m_entry.handled_saved_data[i]=1;
                          }else if(rcmr->childrenHandle[i]==0 &&rcmr->childrenReceive[i]==0 && self_pos-(isSibling-1)==1){
                            log_payload->childrenHandle[i]=1;
                            // backup parent merge child i's msg
                            m_entry.handled_saved_data[i]=1;
                            
                            if(m_entry.saved_data[i].self_data1>0){
                              printf("backup parent %d merge child %d msg\n", (TOS_NODE_ID%500), log_payload->children[i]);
                              log_payload->merged_index[log_payload->curr_num] = m_entry.saved_data[i].source;
                              log_payload->merged_data[log_payload->curr_num] = m_entry.saved_data[i].self_data1;
                              log_payload->curr_num++;
                            }
                            
                            
                            if(m_entry.saved_data[i].curr_num >0){
                              printf("backup parent %d merge child %d msg, total merged data is %d \n", (TOS_NODE_ID%500), log_payload->children[i], m_entry.saved_data[i].curr_num);
                              for(j=0; j<m_entry.saved_data[i].curr_num; j++){
                                printf("merged_index: %d, merged_data: %d, curr_num: %d\n", m_entry.saved_data[i].merged_index[j], m_entry.saved_data[i].merged_data[j], m_entry.saved_data[i].curr_num);
                                log_payload->merged_index[log_payload->curr_num]=m_entry.saved_data[i].merged_index[j];
                                log_payload->merged_data[log_payload->curr_num] = m_entry.saved_data[i].merged_data[j];
                                log_payload->curr_num+=1;
                              }
                            }
                            
                          }
                      }
                  
                  }else if(log_payload->childrenReceive[i]==0){
                      if(isSibling-1 < self_pos && rcmr->childrenHandle[i]==1){
                          log_payload->childrenHandle[i]=1;
                      }
                  
                  }
              
              
              }
              
              
           }

       // if(rcmr->source == 4 && TOS_NODE_ID == ROOT){

			

		//}

		signal Receive.receive(msg, payload, len);
	}	
	
	/** 
	 * Frame configuration
	 * These interfaces are provided for external use, which is misleading as these interfaces are already implemented in GenericClotterC and P
	 */
  	command void Frame.setSlotLength(uint32_t slotTimeBms) {
		atomic slotSize = slotTimeBms;
		call FrameConfiguration.setSlotLength(slotSize);
 	}
 	command void Frame.setFrameLength(uint32_t numSlots) {
 		atomic bi = numSlots;
		call FrameConfiguration.setFrameLength(bi + 1);
 	}
 	command uint32_t Frame.getSlotLength() {
 		return slotSize;
 	}
 	command uint32_t Frame.getFrameLength() {
 		return bi + 1;
 	}
 	
	/**
	 * MISC functions
	 */
	async command void *Send.getPayload(message_t * msg, uint8_t len) {
		return call SubSend.getPayload(msg, len); 
	}
	
	async command uint8_t Send.maxPayloadLength() {
		return call SubSend.maxPayloadLength();
	}
	
	//provide the receive interface
	command void Receive.updateBuffer(message_t * msg) { return call SubReceive.updateBuffer(msg); }
	
	default async event uint16_t CcaControl.getInitialBackoff[am_id_t id](message_t * msg, uint16_t defaultbackoff) {
		return 0;
	}
	
	default async event uint16_t CcaControl.getCongestionBackoff[am_id_t id](message_t * msg, uint16_t defaultBackoff) {
		return 0;
	}
        
	default async event bool CcaControl.getCca[am_id_t id](message_t * msg, bool defaultCca) {
		return FALSE;
	}
	
    event void CC2420Config.syncDone(error_t error){}
    async event void BeaconSend.sendDone(message_t * msg, error_t error){}

    //event void LogWrite.syncDone(error_t error){}
    //event void LogWrite.eraseDone(error_t error){}
    //event void LogWrite.appendDone(void* buf, storage_len_t len, bool recordsLost, error_t error){}
  
    // copy from website
    //event void LogRead.readDone(void* buf, storage_len_t len, error_t err) {}
    //event void LogRead.seekDone(error_t error){}
    
    /*uint8_t get_last_hop_status(uint8_t flow_id_t, uint8_t access_type_t, uint8_t hop_count_t){
    	uint8_t last_hop_status=0;
    	uint8_t i;
    	for (i=0; i<schedule_len; i++){
    		if(schedule[i][0] <= call SlotterControl.getSlot() % superframe_length){
    			if (schedule[i][6]==flow_id_t){//check flow ID
					if(schedule[i][10] == (hop_count_t-1)){//check the previous hop-count
						if(schedule[i][9]==1){
							last_hop_status = schedule[i][9];
							//printf("Sensor:%u, GETTING RECEIVE, Slot:%u, %u, %u, %u, %u, %u , %u, %u, %u, %u, %u.\n", TOS_NODE_ID, schedule[i][0], schedule[i][1], schedule[i][2], schedule[i][3], schedule[i][4], schedule[i][5], schedule[i][6], schedule[i][7], schedule[i][8], schedule[i][9], schedule[i][10]);
						}						
					}
    			}
    		}
		}
		return last_hop_status;
    }//end of get_last_hop_status
    
    void set_current_hop_status(uint32_t slot_t, uint8_t sender, uint8_t receiver){
    	uint8_t i;
    	for (i=0; i<schedule_len; i++){
    		if(schedule[i][0]==slot_t){// check send-receive pairs 1 slot before/after current slot
    			if(schedule[i][1] == sender){//check sender
					if(schedule[i][2] == receiver){//check receiver
						schedule[i][9]=1;
						//printf("Sensor:%u, SETTING RECEIVE, Slot:%u, %u, %u, %u, %u, %u , %u, %u, %u, [9]%u, %u.\n", TOS_NODE_ID, schedule[i][0], schedule[i][1], schedule[i][2], schedule[i][3], schedule[i][4], schedule[i][5], schedule[i][6], schedule[i][7], schedule[i][8], schedule[i][9], schedule[i][10]);
					}
				}
    		}
		}
    }// end of set_current_hop_status
    
    uint8_t get_flow_id(uint32_t slot_t, uint8_t sender, uint8_t receiver){
    	uint8_t i;
    	uint8_t flow_id_t=0;
    	for (i=0; i<schedule_len; i++){
    		if(schedule[i][0]==slot_t){// check send-receive pairs 1 slot before/after current slot
    			if(schedule[i][1] == sender){//check sender
					if(schedule[i][2] == receiver){//check receiver
						flow_id_t=schedule[i][6];
					}
				}
    		}
		}
		return flow_id_t;
    } // end of get_flow_id
      
	void set_send_status(uint32_t slot_at_send_done, uint8_t ack_at_send_done){
   		uint8_t k, i;
   		uint8_t flow_id_at_send_done;
   		uint8_t root_id_at_send_done;
   		uint8_t access_type_at_send_done;
   		
		for (k=0; k<schedule_len; k++){
			if(schedule[k][0] == slot_at_send_done && schedule[k][1] ==TOS_NODE_ID){
				flow_id_at_send_done=schedule[k][6];
				root_id_at_send_done=schedule[k][7];
				access_type_at_send_done=schedule[k][4]; // get the right line of the schedule
			}
		}
	
		//printf("SENSOR:%u, Slot:%u, i:%u\n", TOS_NODE_ID, slot_at_send_done, i);
		if(access_type_at_send_done == 0 || access_type_at_send_done == 2){ // if this is a dedicated slot
		//if(access_type_at_send_done == 0){ // if this is a dedicated slot
			if (ack_at_send_done==1){
				for (i=0; i<schedule_len; i++){
					if (schedule[i][6]==flow_id_at_send_done){ //check flow id
						if(schedule[i][7] == root_id_at_send_done){//check root
							schedule[i][8]=1;
							//printf("***DEDICATED: SENSOR: %u, KILLING POTENTIAL SEND: Slot:%u, %u, %u, %u, %u, %u , %u, %u, %u.\n", TOS_NODE_ID, schedule[i][0], schedule[i][1], schedule[i][2], schedule[i][3], schedule[i][4], schedule[i][5], schedule[i][6], schedule[i][7], schedule[i][8]);
						}
					}
				}
			}
			else{
			}
		}else if(access_type_at_send_done==1){//if this is a shared slot
			//printf("SHARED: SENSOR: %u, DISABLING: Slot:%u, %u, %u, %u, %u, %u , %u, %u, %u.\n", TOS_NODE_ID, schedule[i][0], schedule[i][1], schedule[i][2], schedule[i][3], schedule[i][4], schedule[i][5], schedule[i][6], schedule[i][7], schedule[i][8]);
			if (ack_at_send_done==1){
				//printf("SHARED111: SENSOR: %u, KILLING POTENTIAL SEND: Slot:%u, %u, %u, %u, %u, %u , %u, %u, %u.\n", TOS_NODE_ID, schedule[i][0], schedule[i][1], schedule[i][2], schedule[i][3], schedule[i][4], schedule[i][5], schedule[i][6], schedule[i][7], schedule[i][8]);
			}
			else{
				for (i=0; i<schedule_len; i++){
					if (schedule[i][6]==flow_id_at_send_done){ //check flow id
							schedule[i][8]=1;
					}
				}
				//printf("SHARED222: SENSOR: %u, KILLING POTENTIAL SEND: Slot:%u, %u, %u, %u, %u, %u , %u, %u, %u.\n", TOS_NODE_ID, schedule[i][0], schedule[i][1], schedule[i][2], schedule[i][3], schedule[i][4], schedule[i][5], schedule[i][6], schedule[i][7], schedule[i][8]);
			}
		}
   }// end of set_send_status
   
   	void set_send (uint32_t slot_t){
		uint8_t i;
		uint32_t slot_norm = slot_t; //Here slot_norm is the real time slot normalized by superframe length
		for (i=0; i<schedule_len; i++){	  			
  			if (slot_norm == schedule[i][0]){//check slot  			
  				if(TOS_NODE_ID == schedule[i][1] || TOS_NODE_ID == schedule[i][2]){//check sender & receiver id
  					if(schedule[i][10]>1){ //check if this is on a multi-hop path
  						if(TOS_NODE_ID == schedule[i][1] && schedule[i][8]==0){// problem HERE! why 8? No. 8 in the schedule is Send status in sendDone
  			  				if (get_last_hop_status(schedule[i][6], schedule[i][4], schedule[i][10])){// if above so, check delivery status of last hop
								call CC2420Config.setChannel(schedule[i][3]);
  								call CC2420Config.sync();
  								call AMPacket.setDestination(&packet, schedule[i][2]);
  								call PacketAcknowledgements.requestAck(&packet);
  								
  								call TossimPacketModelCCA.set_cca(schedule[i][4]); //schedule[i][4]: 0, TDMA; 1, CSMA contending; 2, CSMA steal;	
	  							call SubSend.send(&packet, sizeof(TestNetworkMsg));
	  							
	  							//sequence, sender, receiver, access type, slot, channel
	  							//printf("Node: %u, Link Failure detection.\n");
	  							//printf("%u, %u, %u, %u, %u, %u, %u, %u\n", 0, TOS_NODE_ID, schedule[i][2], schedule[i][4], slot_norm, call CC2420Config.getChannel(), schedule[i][5], schedule[i][6]);
	  							
	  							// print out multihop send status
	  							//printf("SENDER, HOP >1: %u->%u, Flow:%u, AccessType:%u, slot: %u, channel: %u, time: %s\n", TOS_NODE_ID, call AMPacket.destination(&packet), schedule[i][6], schedule[i][4], slot_norm, schedule[i][3], sim_time_string());  				  			
  			  				}// end check last hop
  			  			}// end sender check
  			  			if(TOS_NODE_ID == schedule[i][2] && schedule[i][8]==0){
 	 			  				//printf("RECEIVER, HOP >1: %u, slot: %u, channel: %u, time: %s\n", TOS_NODE_ID, slot_norm, schedule[i][3], sim_time_string());
  			  					call CC2420Config.setChannel(schedule[i][3]);
  								call CC2420Config.sync();
  						}//end receiver check
  					}else{
  						if(TOS_NODE_ID == schedule[i][1] && schedule[i][8]==0){
  			  				call CC2420Config.setChannel(schedule[i][3]);
  							call CC2420Config.sync();
  							call AMPacket.setDestination(&packet, schedule[i][2]);
  							call PacketAcknowledgements.requestAck(&packet);
	  						
	  						call TossimPacketModelCCA.set_cca(schedule[i][4]); //schedule[i][4]: 0, TDMA; 1, CSMA contending; 2, CSMA steal;	
	  						call SubSend.send(&packet, sizeof(TestNetworkMsg));
	  						
	  						//printf("Node: %u, Link Failure detection.\n");
	  						//printf("%u, %u, %u, %u, %u, %u, %u, %u\n", 0, TOS_NODE_ID, schedule[i][2], schedule[i][4], slot_norm, call CC2420Config.getChannel(), schedule[i][5], schedule[i][6]);

	  						// print out multihop send status
	  						//printf("SENDER, HOP =1: %u->%u, Flow:%u, AccessType:%u, slot: %u, channel: %u, time: %s\n", TOS_NODE_ID, call AMPacket.destination(&packet), schedule[i][6], schedule[i][4], slot_norm, schedule[i][3], sim_time_string());  				  			
	  					}
  						if(TOS_NODE_ID == schedule[i][2] && schedule[i][8]==0){
	  						//printf("RECEIVER, HOP =1: %u, slot: %u, channel: %u, time: %s\n", TOS_NODE_ID, slot_norm, schedule[i][3], sim_time_string());
  			  				call CC2420Config.setChannel(schedule[i][3]);
  							call CC2420Config.sync();
  						}
  					}//end else
  				}//end slot check
  			}//end sender || receiver check
  		}//end for
   	}*///end set_send
}