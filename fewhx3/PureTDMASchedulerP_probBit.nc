/*
 * "Copyright (c) 2007 Washington University in St. Louis.
 * All rights reserved.
 * @author Wenchen Wang
 * @date $Date: 2014/10/17
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
		MAXCHILDREN = 7,
		TOTALNODES=55,
		NUM_MEASUREMENTS=9,
		SAMPLE_TIMES=2,
		ROOT1=50,
		ADD_THRESHOLD=6,
		REDUCE_THRESHOLD=0,
		//MAXCHILDPARENTS=11,
		
	};

	typedef nx_struct logentry_t{
   
    	TestNetworkMsg ONE saved_data[MAXCHILDREN];
    	nx_uint8_t ONE handled_saved_data[MAXCHILDREN];
    	nx_uint8_t ONE prob_bit[MAXCHILDREN];
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

  	uint8_t receiving_num=0;
  	uint8_t totalChildren=0;
  	uint8_t totalParents=0;

  	uint8_t flag = 0;

  	
  	uint8_t MAXLEVELNODE = 0;

	uint8_t	CURRNODES=0;

  	FILE *fp;

  	FILE *res_fp;

  	//FILE *rev_fp;

  	FILE *delay_fp;

  	FILE * topo_fp;

  	uint8_t starter[12]={1, 7, 14, 18, 22, 26, 30, 34, 38, 42, 46, 50};

  	uint8_t res_list[NUM_MEASUREMENTS] = {0, 0, 0, 0, 0, 0, 0, 0, 0}; // 9 sensor results for root nodes

  	uint8_t delay_list[NUM_MEASUREMENTS] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
  	


  	uint8_t send_counter=0;

  	uint8_t is_primary=0;

  	uint8_t rev_counter=0;

	bool init;
	uint32_t slotSize;
	uint32_t bi, sd, cap;
	uint8_t coordinatorId;

	uint8_t i=0;
	uint8_t j=0;
	uint8_t k=0;
	
	message_t *toSend; //this one will become critical later on, and cause segmentation error
	uint8_t toSendLen;


	uint8_t schedule_counter[12];

	uint8_t up_schedule[12][12];

	uint8_t max_schedule[12]={6, 7, 4, 4, 4, 4, 4, 4, 4, 4, 4, 1};

	//uint8_t curr_schedule_counter[12];

	uint8_t avg_prob=0;

	uint8_t node_list[50];

	uint8_t schedule_len = 0;

	uint8_t num_intervals = 0;

	uint32_t superframe_length = 55; //Real superframe length + 1, to make sure we slot 54 after "%, the mod" processing
	
	bool sync;
	bool requestStop;
	//uint32_t sync_count = 0;
	event void Boot.booted(){}

	void reset_parameters();
	void readTopoFile();
	void generateSchedule();

	int find_delay(int node);

	int find_scounter(int primary_node);

	void generateOnlineTopo();
	
	command error_t Init.init() {		
		//printf("hello!!!!\n");
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

		readTopoFile();

		up_schedule[schedule_len][MAXLEVELNODE+1];

		generateSchedule();

		// init delay list

		for(i=0; i<NUM_MEASUREMENTS; i++){
			delay_list[i] = CURRNODES;
			//printf("ROOT1: %d\n", ROOT1);

		}

		for(i=0; i<MAXCHILDREN; i++){
			m_entry.saved_data[i].curr_num=0;
			m_entry.handled_saved_data[i] =0;

		}

		for(i=0; i<MAXCHILDREN; i++){
			m_entry.prob_bit[i] = 7;
		}

		for(i=0; i<schedule_len; i++){
			for(j=1; j<=up_schedule[i][0]; j++){
				if(TOS_NODE_ID == up_schedule[i][j]){
					log_payload = (TestNetworkMsg*)call Send.getPayload(&m_entry.msg, sizeof(TestNetworkMsg));

					// set children list
					if(i!=0){
						log_payload->totalChildren=up_schedule[i-1][0];
						totalChildren=log_payload->totalChildren;
						for(k=1; k<=up_schedule[i-1][0]; k++){
							log_payload->children[k-1]=up_schedule[i-1][k];
							//printf("Node %d children %d\n", (TOS_NODE_ID%500), log_payload->children[k-1]);
							log_payload->childrenReceive[k-1]=0;
							log_payload->childrenHandle[k-1]=0;
						}
					}else{
						log_payload->totalChildren=0;
						//printf("node total children: %d\n", log_payload->totalChildren);
					}


					// set parent list
					if(i<schedule_len-1){
						log_payload->totalParents=up_schedule[i+1][0];
						totalParents=log_payload->totalParents;
						for(k=1; k<=up_schedule[i+1][0]; k++){
							log_payload->parents[k-1]=up_schedule[i+1][k];
							//printf("Node %d parent %d\n", (TOS_NODE_ID%500), log_payload->parents[k-1]);
						}
					}else{
						log_payload->totalParents=0;
					}
					
					// set sibling list
					log_payload->totalSiblings=up_schedule[i][0];
					for(k=1; k<=up_schedule[i][0]; k++){
						log_payload->siblings[k-1]=up_schedule[i][k];
						//printf("Node %d sibling: %d\n", (TOS_NODE_ID%500), log_payload->siblings[k-1]);
					}

					log_payload->source = TOS_NODE_ID;
					log_payload->curr_num=0;


					/*if(TOS_NODE_ID == 181 || TOS_NODE_ID == 153 || TOS_NODE_ID == 152 || TOS_NODE_ID == 155 || TOS_NODE_ID == 154 
					|| TOS_NODE_ID == 182 || TOS_NODE_ID == 253 || TOS_NODE_ID == 252 || TOS_NODE_ID==255 || TOS_NODE_ID == 254){
						log_payload->self_data1=TOS_NODE_ID;

					}*/
					if(TOS_NODE_ID == 1 || TOS_NODE_ID == 2 || TOS_NODE_ID == 3 || TOS_NODE_ID == 4 || TOS_NODE_ID == 5 
					|| TOS_NODE_ID == 6 || TOS_NODE_ID == 7 || TOS_NODE_ID == 8 || TOS_NODE_ID==9){
						log_payload->self_data1=TOS_NODE_ID*10;
						//printf("self data: %d node %d\n", log_payload->self_data1, TOS_NODE_ID);

					}

					if(j==1){
						log_payload->i_am_primary=1;
						is_primary=1;
					}else{
						log_payload->i_am_primary=0;
						is_primary=0;
					}
					//printf("node %d i_am_primary: %d\n", (TOS_NODE_ID%500), log_payload->i_am_primary);

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
 		//printf("This is sensor: %u and the SplitControl.stop has been reached\n", TOS_NODE_ID);
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
			//printf("This is sensor: %u and the RadioPowerControl.stopDone has been reached\n", TOS_NODE_ID);
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
 		uint8_t scounter;
 		uint8_t add_reduce_counter;

 		//printf("i am node %d at slot %d begining\n", TOS_NODE_ID, slot);
 		
 		if (TOS_NODE_ID == 169){
 				//printf("SENSOR:%u, ABSOLUTE TIME: %s at SLOT:%u.\n", TOS_NODE_ID, sim_time_string(), slot);
 		}
 		
 		if (slot == 0 ) {
 			if (TOS_NODE_ID == 169){
 				//printf("!!!!!!!!SENSOR: %u reached SLOT:%u!!!!!!!!!\n", TOS_NODE_ID, slot);
 			}
 		
 			if (coordinatorId == TOS_NODE_ID) {
 				call BeaconSend.send(NULL, 0);
 				//printf("SENSOR: %u has done network synchronization in SLOT: %u at time: %s:\n", TOS_NODE_ID, slot, sim_time_string());
 			};
 			return;	
 		}
 		
 		if (slot < cap) { 
 		} else {
 			//set_send (slot % superframe_length); //heart beat control
 			//printf("i am node %d at slot: %d\n", TOS_NODE_ID, slot%superframe_length);

 			if(TOS_NODE_ID!=0 && slot%(TOTALNODES+1) ==1 && flag == 0){
 				if (coordinatorId == TOS_NODE_ID) {
 					call BeaconSend.send(NULL, 0);
 				};

 				flag=1;

 				// broadcast initialization messages
 				call CC2420Config.setChannel(22);
  				call CC2420Config.sync();
  				call AMPacket.setDestination(&(m_entry.msg), AM_BROADCAST_ADDR);
  				log_payload = (TestNetworkMsg*)call Send.getPayload(&m_entry.msg, sizeof(TestNetworkMsg));
  				log_payload->source = TOS_NODE_ID;
	  			call SubSend.send(&(m_entry.msg), sizeof(TestNetworkMsg));

	  			send_counter++;

	  			
	  			//printf("Node %d broadcast initialization messages successfully\n", (TOS_NODE_ID%500));

	  			
				//call Init.init();

				//printf("node %d is resetted\n", TOS_NODE_ID);

 			}else if(TOS_NODE_ID!=0 && slot%(TOTALNODES+1) ==1 && flag == 1){

 				//reset nodes merged data and curr_num of m_entry
				reset_parameters();
				if(TOS_NODE_ID == ROOT1){
					for(i=0; i<NUM_MEASUREMENTS; i++){
						printf("res_list: %d\n", res_list[i]);

					}

				}


 			}else if(TOS_NODE_ID!=0 && slot%(TOTALNODES+1)-1 == TOS_NODE_ID){

 				// means I already finished receiving all children messages
              	if(TOS_NODE_ID <= ROOT1 && TOS_NODE_ID!=1 && TOS_NODE_ID!=2 && TOS_NODE_ID!=3 && TOS_NODE_ID!=4 && TOS_NODE_ID!=5 && TOS_NODE_ID!=6){

              		for(i=0; i<log_payload->totalChildren; i++){
              			//printf("node %d payload children receive: %d\n", TOS_NODE_ID, log_payload->childrenReceive[i]);
              			if(log_payload->childrenReceive[i] == 0 && m_entry.prob_bit[i] >0){
              				m_entry.prob_bit[i] --;

              			}

              			//printf("node %d children prob_bit: %d\n", TOS_NODE_ID, m_entry.prob_bit[i]);

              		}

              	}

              	

 				// broadcast messages
 				call CC2420Config.setChannel(22);
  				call CC2420Config.sync();
  				call AMPacket.setDestination(&(m_entry.msg), AM_BROADCAST_ADDR);
  				log_payload = (TestNetworkMsg*)call Send.getPayload(&m_entry.msg, sizeof(TestNetworkMsg));
  				log_payload->source = TOS_NODE_ID;

  				// copy prob_bit to the message
  				for(i=0; i<MAXCHILDREN; i++){
  					log_payload->my_children_prob_bit[i] = m_entry.prob_bit[i];

  				}

	  			call SubSend.send(&(m_entry.msg), sizeof(TestNetworkMsg));

	  			send_counter++;
	  			printf("------------------------------------------Node %d broadcast messages successfully-------------------------------\n", (TOS_NODE_ID%500));

	  			if(TOS_NODE_ID == ROOT1){
	  				  printf("ROOT1: %d\n", ROOT1);
				      printf("setTCPMSG 1: %d %d %d %d %d %d %d %d %d\n", res_list[0], res_list[1], res_list[2], res_list[3], res_list[4], res_list[5], res_list[6], res_list[7], res_list[8]);
				      call SimMote.setTcpMsg(ROOT1, res_list[0], res_list[1], res_list[2], res_list[3], res_list[4], res_list[5], res_list[6], res_list[7], res_list[8]);

				      printf("delay list: %d %d %d %d %d %d %d %d %d\n", delay_list[0], delay_list[1], delay_list[2], delay_list[3], delay_list[4], delay_list[5], delay_list[6], delay_list[7], delay_list[8]);

				      delay_fp=fopen("delay.txt", "a");

				      for(i=0; i<NUM_MEASUREMENTS; i++){
				      	fprintf(delay_fp, "%d %d\n", i+1, delay_list[i]);  
				      }
					              
					  fclose(delay_fp);

		        }


 			}else if(TOS_NODE_ID!=0 && slot%(TOTALNODES+1)-2==ROOT1){
 				num_intervals++;

 				if(TOS_NODE_ID == ROOT1){
 					//printf("print out root %d message receiving %d data\n", TOS_NODE_ID, log_payload->curr_num);
					//fp=fopen("result.txt", "a");
		              //fprintf(fp, "%d\n", log_payload->curr_num);  
		              
		              //fclose(fp);

 				}

 				if(TOS_NODE_ID < ROOT1 && TOS_NODE_ID!=1 && TOS_NODE_ID!=2 && TOS_NODE_ID!=3 && TOS_NODE_ID!=4 && TOS_NODE_ID!=5 && TOS_NODE_ID!=6){
 					res_fp=fopen("result.txt", "a");
		    		fprintf(res_fp, "%d\t%d\t%d\t%f\n", TOS_NODE_ID, receiving_num, totalChildren, (float)receiving_num/(float)totalChildren);         
		    		fclose(res_fp);

		    		receiving_num=0;
 				}

 				if(num_intervals == SAMPLE_TIMES){

              		printf("enter to sample times\n");

					// add nodes according to prob_bits

					// count on itself prob_bit
					for(i=0; i<log_payload->totalChildren; i++){
						avg_prob = avg_prob + m_entry.prob_bit[i];
						printf("Primary %d Add itself prob bit: %d, avg_prob: %d\n", TOS_NODE_ID, m_entry.prob_bit[i], avg_prob);
					}

					if(is_primary==1 && log_payload->totalChildren>0){
						add_reduce_counter = avg_prob/(log_payload->totalChildren*log_payload->totalSiblings);
						printf("node %d totalchildren: %d\n", TOS_NODE_ID, log_payload->totalChildren);
						printf("totalSibling: %d\n", log_payload->totalSiblings);
						printf("total: %d\n", totalChildren*log_payload->totalSiblings);
						printf("avg_prob: %d\n", avg_prob);
						printf("node %d add_reduce_counter: %d\n", TOS_NODE_ID, avg_prob/(totalChildren*log_payload->totalSiblings));


						if(add_reduce_counter <= ADD_THRESHOLD){
							// add one more backup
							printf("primary node %d add one more backup\n", TOS_NODE_ID);
							scounter = find_scounter(TOS_NODE_ID);
							if(scounter>0 && schedule_counter[scounter] < max_schedule[scounter]){
								schedule_counter[scounter]= schedule_counter[scounter]+1;
							}

						}else if(add_reduce_counter >= REDUCE_THRESHOLD){
							// reduce one more backup
							printf("primary node %d reduce one more backup\n", TOS_NODE_ID);
							scounter = find_scounter(TOS_NODE_ID);
							if(scounter>0 && ((scounter >1 && schedule_counter[scounter] >1) || (scounter ==1 && schedule_counter[scounter] > 3)) ){
								schedule_counter[scounter]= schedule_counter[scounter]-1;
							}

						}
					}

					// generate new topology file
					generateOnlineTopo();


					// reset prob_bits
					for(i=0; i<MAXCHILDREN; i++){
						m_entry.prob_bit[i]=7;
					}

					avg_prob = 0;
					num_intervals = 0;
				}

 				

		    	/*rev_fp=fopen("rev.txt", "a");
		    	fprintf(rev_fp, "%d\t%d\n", TOS_NODE_ID, rev_counter);
		    	fclose(rev_fp);
 				
 				if(TOS_NODE_ID == ROOT2){
 					send_fp=fopen("send.txt", "a");
		    		fprintf(send_fp, "###################\n");         
		    		fclose(send_fp);

		    		rev_fp=fopen("rev.txt", "a");
		    		fprintf(rev_fp, "###################\n");
		    		fclose(rev_fp);

		    		//delay_fp=fopen("delay.txt", "a");;
		    		//fprintf(delay_fp, "###################\n");
		    		//fclose(delay_fp);

 				}*/

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
		
		
		
		//printf("RECEIVE: %u->%u, SLOT:%u (time: %s), channel: %u\n", rcmr->source,TOS_NODE_ID, call SlotterControl.getSlot(), sim_time_string(), call CC2420Config.getChannel());

		
           // do fault tolerant bitvector
           isChild = 0;
           isParent=0;
           isSibling=0;
           
           //printf("Node %d log_payload info: totalchildren: %d, totalParents: %d, totalsiblings: %d\n", TOS_NODE_ID, log_payload->totalChildren, log_payload->totalSiblings, log_payload->totalSiblings);

           for(i=0; i<log_payload->totalChildren; i++){
           	  //printf("children: %d\n", log_payload->children[i]);
              if(rcmr->source == log_payload->children[i]){
                isChild=i+1;
              }
           }
           
           //printf("isChild: %d\n", isChild);
           
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
           	  receiving_num += 1;

           	  printf("RECEIVE CHILDREN: %u->%u, SLOT:%u (time: %s), channel: %u\n", rcmr->source,TOS_NODE_ID, call SlotterControl.getSlot(), sim_time_string(), call CC2420Config.getChannel());

           	  // received child message, increase prob bit
           	  if(m_entry.prob_bit[isChild-1] <7 ){
           	  	m_entry.prob_bit[isChild-1] += 1;
           	  }

           	  rev_counter++;

              //printf("node %d found child %d\n", (TOS_NODE_ID%500), rcmr->source);
              if(log_payload->i_am_primary==1){
                  // merge the message of the child
                  
                  log_payload->childrenReceive[isChild-1] = 1;
                  log_payload->childrenHandle[isChild-1] = 1;  
                  
                 
                  if(rcmr->self_data1>0){
                    printf("primary parent %d merge child self data %d message\n", (TOS_NODE_ID%500), rcmr->source);
                    log_payload->merged_index[log_payload->curr_num] = rcmr->source;
                    log_payload->merged_data[log_payload->curr_num] = rcmr->self_data1;

                    if(TOS_NODE_ID == ROOT1){
                    		printf("Node %d source: %d\n", TOS_NODE_ID, rcmr->source);
                    	if(rcmr->source>0 && rcmr->source <= NUM_MEASUREMENTS){
                    		res_list[rcmr->source-1] = rcmr->source; 
                    		delay_list[rcmr->source-1] = find_delay(call SlotterControl.getSlot() % (TOTALNODES+1));
                    		printf("1----res_list: %d\n", res_list[rcmr->source-1]);
                    		//delay_fp=fopen("delay.txt", "a");
                    		printf("1----%d %d %d %d\n", rcmr->source, call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());
						    //fprintf(delay_fp, "%d %d %d %d\n", rcmr->source, call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());  
						              
						    //fclose(delay_fp);

                    	}
                    	
                    }
                    

                    log_payload->curr_num++;
                  }
                  
                  
                  if(rcmr->curr_num >0){
                    printf("primary parent %d merge child %d message\n", (TOS_NODE_ID%500), rcmr->source);
                    for(i=0; i<rcmr->curr_num; i++){
                      log_payload->merged_index[log_payload->curr_num]=rcmr->merged_index[i];
                      log_payload->merged_data[log_payload->curr_num] = rcmr->merged_data[i];
                      log_payload->curr_num++;

                      if(TOS_NODE_ID == ROOT1){

                      	
                      	printf("Node %d source: %d\n", TOS_NODE_ID, rcmr->source);
                      	if(rcmr->merged_index[i]>0 && rcmr->merged_index[i] <= NUM_MEASUREMENTS){
                      		res_list[rcmr->merged_index[i]-1] = rcmr->merged_index[i]; 
                      		//printf("2----res_list: %d\n", res_list[rcmr->merged_index[i]-1]);
                      		delay_list[rcmr->merged_index[i]-1] = find_delay(call SlotterControl.getSlot() % (TOTALNODES+1));
                      		//delay_fp=fopen("delay.txt", "a");
                      		//printf("2----%d %d %d %d\n", rcmr->merged_index[i], call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());
						    //fprintf(delay_fp, "%d %d %d %d\n", rcmr->merged_index[i], call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());   
						    //fclose(delay_fp);

                      	}

                      	
                      }

                    }
                  }
                  
              }else{
                  // save the message of the child
                 
                  log_payload->childrenReceive[isChild-1] = 1;
                  log_payload->childrenHandle[isChild-1] = 0;  
                  
                  if(rcmr->self_data1>0){
                    //printf("backup parent %d save child %d self data\n", (TOS_NODE_ID%500), rcmr->source);
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
              
              if(TOS_NODE_ID!=1 && TOS_NODE_ID!=2 && TOS_NODE_ID!=3 && TOS_NODE_ID!=4 && TOS_NODE_ID!=5 
              && TOS_NODE_ID!=6 && TOS_NODE_ID!=7 && TOS_NODE_ID!=8 && TOS_NODE_ID!=9){
              		log_payload->self_data1=0;

              }
              
           }else if(isParent >=1){
              // do nothing
              //receiving_num += 1;
              //printf("%d is parent of %d\n", rcmr->source,TOS_NODE_ID);

               //printf("RECEIVE PARENT: %u->%u, SLOT:%u (time: %s), channel: %u\n", rcmr->source,TOS_NODE_ID, call SlotterControl.getSlot(), sim_time_string(), call CC2420Config.getChannel());
           
           }else if(isSibling >=1){
           	   //printf("RECEIVE SIBLING: %u->%u, SLOT:%u (time: %s), channel: %u\n", rcmr->source,TOS_NODE_ID, call SlotterControl.getSlot(), sim_time_string(), call CC2420Config.getChannel());

           	   // receive a message from a sibling

           	   if(is_primary==1 && num_intervals== SAMPLE_TIMES-1){
           	   		printf("node %d receive sibling message\n", TOS_NODE_ID);
           	   		for(i=0; i<log_payload->totalChildren; i++){
           	   			avg_prob = avg_prob +log_payload->my_children_prob_bit[i];
           	   			printf("Primary %d Add sibling %d prob bit: %d\n", TOS_NODE_ID, rcmr->source, log_payload->my_children_prob_bit[i]);
           	   		}
           	   }

           	  rev_counter++;

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
                              //printf("backup parent %d merge child %d msg\n", (TOS_NODE_ID%500), log_payload->children[i]);
                              log_payload->merged_index[log_payload->curr_num] = m_entry.saved_data[i].source;
                              log_payload->merged_data[log_payload->curr_num] = m_entry.saved_data[i].self_data1;
                              log_payload->curr_num++;

                              //printf("Node %d source: %d\n", TOS_NODE_ID, rcmr->source);

                              if(TOS_NODE_ID == ROOT1){
                              	if(m_entry.saved_data[i].source >0 && m_entry.saved_data[i].source <= NUM_MEASUREMENTS){
                              		res_list[m_entry.saved_data[i].source-1] = m_entry.saved_data[i].source; 
                              		delay_list[m_entry.saved_data[i].source-1] = find_delay(call SlotterControl.getSlot() % (TOTALNODES+1));
                              		//printf("3-----res_list: %d\n", res_list[m_entry.saved_data[i].source-1]);
                              		//delay_fp=fopen("delay.txt", "a");
                              		//printf("3----%d %d %d %d\n", m_entry.saved_data[i].source, call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());
					    			//fprintf(delay_fp, "%d %d %d %d\n", m_entry.saved_data[i].source, call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());  
					              
					    			//fclose(delay_fp);

                              	}

                              }

                            }
                            
                            
                            if(m_entry.saved_data[i].curr_num >0){
                              //printf("backup parent %d merge child %d msg, total merged data is %d \n", (TOS_NODE_ID%500), log_payload->children[i], m_entry.saved_data[i].curr_num);
                              for(j=0; j<m_entry.saved_data[i].curr_num; j++){
                                //printf("merged_index: %d, merged_data: %d, curr_num: %d\n", m_entry.saved_data[i].merged_index[j], m_entry.saved_data[i].merged_data[j], m_entry.saved_data[i].curr_num);
                                log_payload->merged_index[log_payload->curr_num]=m_entry.saved_data[i].merged_index[j];
                                log_payload->merged_data[log_payload->curr_num] = m_entry.saved_data[i].merged_data[j];
                                log_payload->curr_num+=1;
                                if(TOS_NODE_ID == ROOT1){

                                	if(m_entry.saved_data[i].merged_index[j]>0 && m_entry.saved_data[i].merged_index[j] <= NUM_MEASUREMENTS){
                                		res_list[m_entry.saved_data[i].merged_index[j]-1] = m_entry.saved_data[i].merged_index[j]; 
                                		delay_list[m_entry.saved_data[i].merged_index[j]-1] = find_delay(call SlotterControl.getSlot() % (TOTALNODES+1));
                                		//printf("4----res_list: %d\n", m_entry.saved_data[i].merged_index[j]);
                              			//printf("4----%d %d %d %d\n", m_entry.saved_data[i].merged_index[j], call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());
                              			//delay_fp=fopen("delay.txt", "a");
					    				//fprintf(delay_fp, "%d %d %d %d\n", m_entry.saved_data[i].merged_index[j], call SlotterControl.getSlot() % (TOTALNODES+1), TOS_NODE_ID, call CC2420Config.getChannel());  					    
					    				//fclose(delay_fp);

                                	}
                              		

                              	}

                              }
                            }

                            /*if(TOS_NODE_ID == ROOT1){

							      printf("setTCPMSG 2: %d %d %d %d %d %d %d %d %d\n", res_list[0], res_list[1], res_list[2], res_list[3], res_list[4], res_list[5], res_list[6], res_list[7], res_list[8]);
							      call SimMote.setTcpMsg(ROOT1, res_list[0], res_list[1], res_list[2], res_list[3], res_list[4], res_list[5], res_list[6], res_list[7], res_list[8]);

							      // reset res_list
							       for(i=0; i<NUM_MEASUREMENTS; i++){
							       		res_list[i]=0;
							       }

			       			}*/
                            
                          }
                      }
                  
                  }else if(log_payload->childrenReceive[i]==0){
                      if(isSibling-1 < self_pos && rcmr->childrenHandle[i]==1){
                          log_payload->childrenHandle[i]=1;
                      }
                  
                  }
              
              
              }
              
              

           }

      

        

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

    void readTopoFile(){
    	
   		char * line = NULL;
   		size_t len = 0;
   		ssize_t read;

   		uint8_t line_counter=0;

   		char *token;

   		uint8_t counter =0;
    	
	   	//ssize_t read;

	   	topo_fp = fopen("/Users/wangwenchen/wcps_apps/space_faults_addnodes_strategy/topology.txt", "r");
	   	if (topo_fp == NULL)
	       exit(EXIT_FAILURE);

	   	while (getline(&line, &len, topo_fp) != -1) {
	       //printf("Retrieved line of length %zu :\n", read);
	       //printf("%s", line.data);

	       
	       token = NULL;
	       counter=0;

	       /* get the first token */
	       token = strtok(line, " ");
	       //printf("first token: %s\n", token);
	       
	       /* walk through other tokens */
	       while( token != NULL ) 
	       {
	          //printf( " %s\n", token );
	        
	          token = strtok(NULL, " ");
	          //printf("other tokens: %s\n", token);
	          counter++;
	       }

	       if(MAXLEVELNODE < counter && line_counter!=0){
	          MAXLEVELNODE = counter;
	       }


	       //printf("counter: %d\n", counter);

	       if(line_counter==0){
	          CURRNODES = counter;
	       }else{
	          schedule_counter[line_counter-1] = counter;

	       }

	       line_counter++;
	   
	   }

	   

	   //printf("line_counter: %d\n", line_counter);
	   schedule_len = line_counter-1;

	   //printf("ROOT1: %d\n", ROOT1);
	   //printf("MAXLEVELNODE: %d\n", MAXLEVELNODE);
	   //printf("schedule_len: %d\n", schedule_len);

	   fclose(topo_fp);

	   if (line){
	   		free(line);
	   }
       		

    }

    int find_delay(int node){
    	uint8_t i;
    	for(i=0; i<CURRNODES; i++){
    		if(node_list[i] == node){
    			return i+1;
    		}

    	}

    	return CURRNODES;

    }


    void reset_parameters(){
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


		readTopoFile();

		// reset res_list
       	for(i=0; i<NUM_MEASUREMENTS; i++){
       		res_list[i]=0;
       	}

       	printf("CURRNODES: %d\n", CURRNODES);

       	// reset res_list
       	for(i=0; i<NUM_MEASUREMENTS; i++){
       		delay_list[i]=CURRNODES;
       	}


		up_schedule[schedule_len][MAXLEVELNODE+1];


		generateSchedule();

		for(i=0; i<MAXCHILDREN; i++){
			m_entry.saved_data[i].curr_num=0;
			m_entry.handled_saved_data[i] =0;

		}

		for(i=0; i<schedule_len; i++){
			for(j=1; j<=up_schedule[i][0]; j++){
				if(TOS_NODE_ID == up_schedule[i][j]){
					log_payload = (TestNetworkMsg*)call Send.getPayload(&m_entry.msg, sizeof(TestNetworkMsg));

					// set children list
					if(i!=0){
						log_payload->totalChildren=up_schedule[i-1][0];
						totalChildren=log_payload->totalChildren;
						for(k=1; k<=up_schedule[i-1][0]; k++){
							log_payload->children[k-1]=up_schedule[i-1][k];
							//printf("Node %d children %d\n", (TOS_NODE_ID%500), log_payload->children[k-1]);
							log_payload->childrenReceive[k-1]=0;
							log_payload->childrenHandle[k-1]=0;
						}
					}else{
						log_payload->totalChildren=0;
						//printf("node total children: %d\n", log_payload->totalChildren);
					}


					// set parent list
					if(i<schedule_len-1){
						log_payload->totalParents=up_schedule[i+1][0];
						totalParents=log_payload->totalParents;
						for(k=1; k<=up_schedule[i+1][0]; k++){
							log_payload->parents[k-1]=up_schedule[i+1][k];
							//printf("Node %d parent %d\n", (TOS_NODE_ID%500), log_payload->parents[k-1]);
						}
					}else{
						log_payload->totalParents=0;
					}
					
					// set sibling list
					log_payload->totalSiblings=up_schedule[i][0];
					for(k=1; k<=up_schedule[i][0]; k++){
						log_payload->siblings[k-1]=up_schedule[i][k];
						//printf("Node %d sibling: %d\n", (TOS_NODE_ID%500), log_payload->siblings[k-1]);
					}

					log_payload->source = TOS_NODE_ID;
					log_payload->curr_num=0;


					/*if(TOS_NODE_ID == 181 || TOS_NODE_ID == 153 || TOS_NODE_ID == 152 || TOS_NODE_ID == 155 || TOS_NODE_ID == 154 
					|| TOS_NODE_ID == 182 || TOS_NODE_ID == 253 || TOS_NODE_ID == 252 || TOS_NODE_ID==255 || TOS_NODE_ID == 254){
						log_payload->self_data1=TOS_NODE_ID;

					}*/
					if(TOS_NODE_ID == 1 || TOS_NODE_ID == 2 || TOS_NODE_ID == 3 || TOS_NODE_ID == 4 || TOS_NODE_ID == 5 
					|| TOS_NODE_ID == 6 || TOS_NODE_ID == 7 || TOS_NODE_ID == 8 || TOS_NODE_ID==9){
						log_payload->self_data1=TOS_NODE_ID*10;
						//printf("self data: %d node %d\n", log_payload->self_data1, TOS_NODE_ID);

					}

					if(j==1){
						log_payload->i_am_primary=1;
					}else{
						log_payload->i_am_primary=0;
					}
					//printf("node %d i_am_primary: %d\n", (TOS_NODE_ID%500), log_payload->i_am_primary);

				}

			}
		}	

    }

    void generateSchedule(){
    	char * line = NULL;
   		size_t len = 0;
   		ssize_t read;

   		uint8_t line_counter=0;

   		char *token;

   		uint8_t counter =0;

   		uint8_t i, j;

   		uint8_t node_index=0;

   		node_list[CURRNODES];

   		

    	   topo_fp = fopen("/Users/wangwenchen/wcps_apps/space_faults_addnodes_strategy/topology.txt", "r");

		   if (topo_fp == NULL)
		       exit(EXIT_FAILURE);

		   // read the first line
		   getline(&line, &len, topo_fp);
		   line_counter=0;
		   
		   
		    while ((read = getline(&line, &len, topo_fp)) != -1) {

		       int counter=0;

		       	  //printf("schedule counter: %d\n", schedule_counter[line_counter]);
		       	  //printf("line_counter: %d\n", line_counter);
		          up_schedule[line_counter][counter] = schedule_counter[line_counter];

		      	  //printf("schedule counter: %d\n", up_schedule[line_counter][counter]);
		       
		       /* get the first token */
		       token = strtok(line, " ");
		       counter++;
		       //printf("first schedule token: %s\n", token);
		       
		       up_schedule[line_counter][counter] = atoi(token);

		       //printf("up_schedule: %d\n", up_schedule[line_counter][counter]);
		       

		       /* walk through other tokens */
		       while( token != NULL ) 
		       {
		          //printf( " %s\n", token );
		        
		          token = strtok(NULL, " ");
		         
		          counter++;

		          if(counter <=schedule_counter[line_counter]){
		            //printf("other schedule tokens: %s\n", token);
		            up_schedule[line_counter][counter] = atoi(token);




		            //printf("up_schedule: %d\n", up_schedule[line_counter][counter]);
		          }
		          
		       }

		       line_counter++;
		   
		    }

		    // display up_schedule
		    
		    for(i=0; i<schedule_len; i++){
		      //printf("%d line of schedule: \n", i);
		      for(j=1; j<=up_schedule[i][0]; j++){
		        //printf("%d ", up_schedule[i][j]);

		        node_list[node_index] = up_schedule[i][j];

		        //printf("%d ", node_list[node_index]);
		        node_index += 1;

		      }

		      //printf("\n");

		    }


		   fclose(topo_fp);

    }

    int find_scounter(int primary_node){
    	if(primary_node == 1){
    		return 0;
    	}else if(primary_node == 7){
    		return 1;
    	}else if(primary_node == 14){
    		return 2;
    	}else if(primary_node == 18){
    		return 3;
    	}else if(primary_node == 22){
    		return 4;
    	}else if(primary_node == 26){
    		return 5;
    	}else if(primary_node == 30){
    		return 6;
    	}else if(primary_node == 34){
    		return 7;
    	}else if(primary_node == 38){
    		return 8;
    	}else if(primary_node == 42){
    		return 9;
    	}else if(primary_node == 46){
    		return 10;
    	}else if(primary_node == 50){
    		return 11;
    	}
    	return -1;
    }

	void generateOnlineTopo(){

		int counter;

		int i, j;

		FILE *fp_new_topo;

		fp_new_topo = fopen("/Users/wangwenchen/wcps_apps/space_faults_addnodes_strategy/topology.txt", "w");

		for(i=0; i<12; i++){
			counter = starter[i];
			for(j=0; j<schedule_counter[i]; j++){
				fprintf(fp_new_topo, "%d", counter);
				if(j!=schedule_counter[i]-1){
					fprintf(fp_new_topo, " ");
				}
				counter++;
			}
			//topo << "\n";
			fprintf(fp_new_topo, "\n");
		}

		fclose(fp_new_topo);
	}

}