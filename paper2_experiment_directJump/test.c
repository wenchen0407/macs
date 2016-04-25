#include <stdio.h>
#include <stdlib.h>
#include <string.h>


	int read_rev_file(){
		// read topo_update_log.txt file and generate new network topology by ROOT
		FILE * topo_fp;
	   	char * line = NULL;
	   	size_t len = 0;
	   	ssize_t read;
	   	int i;
	   	char *token;
	   	int line_counter=0;
	   
	   	topo_fp = fopen("/Users/wangwenchen/github/paper2_experiment/received_situation.txt", "r");
	  	if (topo_fp == NULL){
	  		printf("No file???\n");
	       	return 0;
	    }

	   	getline(&line, &len, topo_fp);

	   	token = strtok(line, " ");

	   	measurements_received = atoi(token);
	   	printf("Node %d measuremnt received: %d\n", TOS_NODE_ID, measurements_received);

	   	token = strtok(NULL, " ");
	   	curr_network_delay= atof(token);

	   	printf("token:%s", token);

	   	printf("Node %d network delay: %d\n", TOS_NODE_ID, curr_network_delay);


	  	return 1;

	}

	int main(){

		read_rev_file();
	}