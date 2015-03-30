#!/bin/sh

### USAGE
usage(){
    echo -e "\n\n"
    echo "USAGE:  $(basename $0) -s /path/to/source/vmdk -d /path/to/new/vm [-n X] [-m Y] [-f] [-h]"
    echo 
    echo "    where:"
    echo "        -s  - Source drive.  Path to source drive vmdk or snapshot.vmdk to use "
    echo "              as basis for cloning"
    echo "        -d  - Destination.  Directory that should be created to house the new "
    echo "              vms files"
    echo "        -n  - Number of network interfaces (1-10).  Optional argument.  Default is 1."
    echo "        -m  - Amount of memory allocated to machine in megabytes.  Use G "
    echo "              suffix to specify gigabytes.  Optional argument.  Default is 1 "
    echo "              Gbyte." 
    echo "        -f  - Force cloning.  Bypasses user prompts, for use with scripting.  Optional"
    echo "              argument."
    echo "        -h  - Help.  this usage statement."
    echo -e "\n\n"
}


### PARSE COMMAND LINE OPTIONS
OPTIND=1;

while getopts "s:d:n:m:h" opt; do

    case "$opt" in
    
        s)
            SOURCE_VMDK=$OPTARG
            ;;
        d)  
            VM_DIR=$OPTARG
            ;;
        n)
            NIC_COUNT=$OPTARG
            ;;
        m)
            MEMORY=$OPTARG
            ;;
        h)  
            usage
            exit 0
            ;;
        '?')
            usage >&2
            exit 1
            ;;
    esac
 
done



### SET DEFAULT VALUES (IF NOT PROVIDED)
NIC_COUNT=${NIC_COUNT:-1}
MEMORY=${MEMORY:-1024}

### CHECK OPTIONS

if [ "x$SOURCE_VMDK" = "x" ]; then

    echo -e "\nERROR:  No source VMDK provided.  Please specify one using the -s option"
    usage
    exit 1

elif ! $(echo $SOURCE_VMDK | grep -qie"\.vmdk$") ; then

    echo -e "\nERROR:  Source disk is not a vmdk.  Please specify a vmdk file using the -s "
    echo    "        option."
    usage
    exit 1
    
elif [ ! -e "$SOURCE_VMDK" ]; then

    echo -e "\nERROR:  Source disk provided does not exist.  Please specify an existing VMDK "
    echo    "        using the -s option"
    usage
    exit 1

fi
#SHOULD PROBABLY REVISIT TO ADD OPEN FILE CHECK (ONCE ITS FIGURED OUT)

if [ "x$VM_DIR" = "x" ]; then                                              
                                                                                
    echo -e "\nERROR:  No destination directory provided.  Please specify one using the -d "
    echo    "        option"
    usage                                                                       
    exit 1                                                                      
                                                                                                                                                                            
elif [ -e "$VM_DIR" ]; then                                              
                                                                                                                                                                                                                                                                                                                                                                                                                                        
    echo -e "\nERROR:  Destination directory exists (can't create a new VM in this location). "
    echo    "        Please specify a nonexistent directory using the -d option."
    usage                                                                       
    exit 1                                                                      
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    
fi

if [ $(( $NIC_COUNT + 100 )) -lt 101 ] || [ $(( $NIC_COUNT + 100 )) -gt 110 ]; then

    echo -e "\nERROR:  Number of network interfaces is not between 1 and 10.  Please specify "
    echo    "        using the -n option (or omit for the default of 1)."
    usage
    exit 1
fi

if $(echo $MEMORY | grep -qe 'G$'); then
    
    MEMORY=$(( $(echo $MEMORY |grep -oe '[0-9]*') * 1024 ))

fi

MEMORY=$(echo $MEMORY|grep -oe '[0-9]*')

if [ $(( $MEMORY + 0 )) -lt 1 ]; then
 
    echo -e "\nERROR:  At least 1 MB must be specified for the VM (and probably much more)."
    echo    "        Please specify an amount of memory using the -m option (or omit for"
    echo    "        for the default of 1GB"
    usage
    exit 1

fi  


### PRINT VALUES
echo -e "\n\n"
echo "Cloning VM with the following values:"
echo "    Source drive                 = $SOURCE_VMDK"
echo "    New VM path                  = $VM_DIR"
echo "    Number of Network Interfaces = $NIC_COUNT"
echo "    Memory allocated to VM       = $MEMORY MB"
echo
echo "Press ENTER to start the cloning process"

if [ "x$AUTO" = "x" ]; then
    echo "Press ENTER to start the cloning process"
    read
fi
        

#### START THE CLONING PROCESS
 
#1) Create fresh VM.  Created VM number is returned, will be referenced from here on out
echo "STEP 1.  Create the dummy VM..."
VM_DIR="$(echo $VM_DIR|sed 's/\/$//')"
VM_DIR_NAME="$(echo $VM_DIR|grep -oe '[^/]*$')"
VM_DIR_PATH="$(echo $VM_DIR|grep -oe '^.*/')"

VM_ID="$(vim-cmd vmsvc/createdummyvm "$VM_DIR_NAME" "$VM_DIR_PATH")"
echo "    ...done"
echo

#2) Delete disk created. Controller ID can be gained from vim-cmd vmsvc/device.getdevice $VM_ID (probably will always be 1000)
echo "STEP 2.  Remove the dummy's virtual disk..."
vim-cmd vmsvc/device.diskremove $VM_ID controller number 1000
echo "    ...done"
echo

#3) Clone the disk into the new VM
echo "STEP 3.  Clone the source disk into the dummy VM directory..."
vmkfstools -i "$SOURCE_VMDK"  -d thin "$VM_DIR/$VM_DIR_NAME.vmdk" 
echo "    ...done"
echo

#4) Add the disk to the new Vm
echo "STEP 4.  Add the cloned disk to the dummy VM..."
vim-cmd vmsvc/device.diskaddexisting $VM_ID "$VM_DIR/$VM_DIR_NAME.vmdk" 1000 1
echo "    ...done"
echo

#5) Add NIC.  Get unit ID by picking unused number.  Existing numbers are found with vim-cmd vmsvc/device.getdevices 7 | grep unitN
#umber
echo "STEP 5.  Add Network Interfaces"
export INTERFACE_NUMBER=0
for COUNTER in $(seq 1 $NIC_COUNT); do
    export DEVICE_LIST=" $(vim-cmd vmsvc/device.getdevices $VM_ID|grep unitNumber|grep -oe '[0-9]*'|xargs) "
    INTERFACE_NUMBER=$(( $INTERFACE_NUMBER + 1 ))
    echo "$DEVICE_LIST" |grep -q " $INTERFACE_NUMBER "
    while [ $? -eq 0 ]; do 
        INTERFACE_NUMBER=$(( $INTERFACE_NUMBER + 1 ))
        echo "$DEVICE_LIST" |grep -q " $INTERFACE_NUMBER " 
    done
    echo "  - Adding interface $COUNTER as device $INTERFACE_NUMBER"
    vim-cmd vmsvc/devices.createnic $VM_ID $INTERFACE_NUMBER "e1000" "VM Network"
done
echo "    ...done"
echo

#6) Add memory to the VM
echo STEP6.  Configure VM memory...
cat "$VM_DIR/$VM_DIR_NAME.vmx"|grep -v memSize > "$VM_DIR/$VM_DIR_NAME.vmx.tmp"
echo "memSize = \"$MEMORY\"" >> "$VM_DIR/$VM_DIR_NAME.vmx.tmp"
mv "$VM_DIR/$VM_DIR_NAME.vmx.tmp" "$VM_DIR/$VM_DIR_NAME.vmx" 
echo "   ...done"

echo -e "\n\n"
echo "Process complete.  Assuming everything worked, you should now have a working clone.  Enjoy"
echo -e "\n\n"
