<!-- Example Job 1: approve_rejectedItemsCycleCount  -->
<moqui.service.job.ServiceJob jobName="approve_rejectedItemsCycleCount"
                              jobTypeEnumId="JOB_REJ_ITEM_COUNT"
                              instanceOfProductId="JOB_REJ_ITEM_COUNT"
                              description="Template Service Job to approve cycle counts created for rejected items"
                              serviceName="co.hotwax.cycleCount.InventoryCountServices.approve#InventoryCountImport"
                              paused="Y">
    <parameters parameterName="countTypeEnumId" parameterValue="REJ_ITEM_COUNT"/>
    <parameters parameterName="productStoreId" parameterValue=""/>
</moqui.service.job.ServiceJob>

<!-- Example Job 2: approve_rejectedItemsCycleCount_STORE -->
<moqui.service.job.ServiceJob jobName="approve_rejectedItemsCycleCount_STORE"
                              jobTypeEnumId="JOB_REJ_ITEM_COUNT"
                              instanceOfProductId="JOB_REJ_ITEM_COUNT"
                              description="Approve cycle counts created for rejected items for STORE"
                              serviceName="co.hotwax.cycleCount.InventoryCountServices.approve#InventoryCountImport"
                              paused="Y">
    <parameters parameterName="countTypeEnumId" parameterValue="REJ_ITEM_COUNT"/>
    <parameters parameterName="productStoreId" parameterValue="STORE"/>
</moqui.service.job.ServiceJob>
