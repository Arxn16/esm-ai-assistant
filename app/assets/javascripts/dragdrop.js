var srcDrag;
var printable=10;
var pic_dx=0;
var pic_dy=0;
//------------------------------------------------------------------
function getX(el){
	var absX=0;
	while(el!=null){
		absX += el.offsetLeft;
		el = el.offsetParent;
	}
	return absX;
}
//------------------------------------------------------------------
function getY(el){
	var absY=0;
	while(el!=null){
		absY += el.offsetTop;
		el = el.offsetParent;
	}
	return absY;
}

//------------------------------------------------------------------
function findTopNode(node){
	var el=node;
	while(el!=null){
		if((el.tagName=='DIV')&&(el.id.substring(0,3)=='pic'))
			break;
		el = el.parentNode;
	}
	return el;
}
//------------------------------------------------------------------
function redisplay_printzone(){
	var pics = document.getElementById('pictzone');

	for(i=0;i<pics.children.length-1;i++){
		pics.children[i].className = (i<printable) ? "eachpicprint" : "eachpic";
	}
}
//------------------------------------------------------------------
function beginDrag(){
	var el = event.srcElement;
	while(el!=null){
		if((el.tagName=='DIV')&&(el.id.substring(0,3)=='pic'))
			break;
		el = el.parentNode;
	}
	if(el!=null){
		srcDrag = el;
	}
}
//------------------------------------------------------------------
function dragEnter(){	
}
//------------------------------------------------------------------
function dragOut()
{
	var el = findTopNode(event.srcElement);
	el.style.borderLeftColor=el.style.backgroundColor;
	document.getElementById('indicator').style.visibility="hidden";
}
//------------------------------------------------------------------
function dragDrop()
{
	endDrag();
	var el = findTopNode(event.srcElement);

	el.style.borderColor=el.style.backgroundColor;
	if((srcDrag!=null)&&(el.id!=srcDrag.id)){
		document.getElementById('pictzone').insertBefore(srcDrag,el);
		redisplay_printzone();
	}
}
//------------------------------------------------------------------
function dragOver()
{
	event.returnValue = false ;
	var el = findTopNode(event.srcElement);
	var ind = document.getElementById('indicator');

	if(el!=null){
		el.style.borderLeftColor="#FF6600";
		ind.style.visibility="visible";
		ind.style.left = (pic_dx + el.offsetLeft-8)+"px";
		ind.style.top  = (pic_dy + el.offsetTop-35)+"px";
	}else
		ind.style.visibility="hidden";
}
//------------------------------------------------------------------
function endDrag(){
	document.getElementById('indicator').style.visibility="hidden";
}
//------------------------------------------------------------------
function traskOver(){
	event.returnValue = false; 
	document.getElementById('trash').style.backgroundImage='url("/dragdrop/images/trash3.png")';
}
//------------------------------------------------------------------
function trashOut(){
	document.getElementById('trash').style.backgroundImage='url("/dragdrop/images/trash2.png")';
}
//------------------------------------------------------------------
function trashDrop(){
	trashOut();
	document.getElementById('pictzone').removeChild(srcDrag);
	redisplay_printzone();
}
//------------------------------------------------------------------
function trashRemove(id){
	trashOut();
	element = document.getElementById(id)
	document.getElementById('pictzone').removeChild(element);
	redisplay_printzone();
}
//------------------------------------------------------------------
function showFullPic(){
	var el=findTopNode(event.srcElement);
	window.open("/webcam/show/"+el.id,"fullpict",
			"titlebar=no,toolbar=no,status=no,width=860,height=700",true);
}
//------------------------------------------------------------------
function getCoorPictZn(){
	el=document.getElementById('pictzone');
	pic_dx = getX(el);
	pic_dy = getY(el);
}